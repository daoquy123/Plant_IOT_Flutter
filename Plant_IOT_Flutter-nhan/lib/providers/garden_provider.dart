import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/server_defaults.dart';
import '../data/esp32_client.dart';
import '../models/sensor_display.dart';
import 'settings_provider.dart';

/// Trạng thái chung cho Dashboard và Điều khiển — đồng bộ qua server Node.js.
class GardenProvider extends ChangeNotifier {
  GardenProvider({Esp32Client? esp32}) : _esp32 = esp32 ?? Esp32Client();

  final Esp32Client _esp32;
  SettingsProvider? _settings;

  io.Socket? _socket;
  String? _socketBase;
  final List<void Function(String imageUrl)> _captureDoneListeners = [];

  void _notifyCaptureListeners(String url) {
    final u = url.trim();
    if (u.isEmpty) return;
    for (final listener in List<void Function(String imageUrl)>.from(_captureDoneListeners)) {
      listener(u);
    }
  }

  /// Snapshot of latest DB row + URL (for detecting new upload after capture).
  _CameraSnapshot? _parseLatestImageMap(Map<String, dynamic> map) {
    final rawImage = map['image'];
    if (rawImage is! Map) return null;
    final m = Map<String, dynamic>.from(rawImage);
    final url = m['url']?.toString().trim();
    if (url == null || url.isEmpty) return null;
    return _CameraSnapshot(
      id: m['id'],
      capturedAt: m['captured_at']?.toString(),
      url: url,
    );
  }

  Future<_CameraSnapshot?> _fetchLatestCameraSnapshot() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) return null;
    try {
      final map = await _esp32.fetchLatestImage(serverBase: base, apiKey: apiKey);
      return _parseLatestImageMap(map);
    } catch (_) {
      return null;
    }
  }

  static String cacheBustUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final sep = u.contains('?') ? '&' : '?';
    return '$u${sep}cb=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Request capture on server, then wait for a new row in DB (poll) and/or socket `capture-done` / `camera`.
  Future<String?> waitForNewCameraImageAfterRequest({
    Duration timeout = const Duration(seconds: 25),
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return null;
    }

    final before = await _fetchLatestCameraSnapshot();
    final requestStartedAt = DateTime.now().toUtc();
    await requestCapture();

    final completer = Completer<String?>();
    Timer? pollTimer;

    bool isNewSnapshot(_CameraSnapshot snap) {
      if (before != null) {
        return snap.id != before.id ||
            snap.capturedAt != before.capturedAt ||
            snap.url != before.url;
      }
      final cap = snap.capturedAt;
      if (cap == null || cap.isEmpty) return false;
      try {
        final t = DateTime.parse(cap).toUtc();
        return !t.isBefore(requestStartedAt.subtract(const Duration(seconds: 3)));
      } catch (_) {
        return false;
      }
    }

    void completeOnce(String? url) {
      if (completer.isCompleted) return;
      if (url != null && url.trim().isNotEmpty) {
        latestImageUrl = url.trim();
        notifyListeners();
        completer.complete(cacheBustUrl(url.trim()));
      }
    }

    late void Function(String imageUrl) socketListener;
    socketListener = (imageUrl) {
      if (completer.isCompleted) return;
      removeCaptureDoneListener(socketListener);
      completeOnce(imageUrl);
    };
    addCaptureDoneListener(socketListener);

    Future<void> pollOnce() async {
      if (completer.isCompleted) return;
      final snap = await _fetchLatestCameraSnapshot();
      if (snap == null) return;
      if (isNewSnapshot(snap)) {
        removeCaptureDoneListener(socketListener);
        completeOnce(snap.url);
      }
    }

    Future.microtask(pollOnce);
    pollTimer = Timer.periodic(pollInterval, (_) {
      Future.microtask(pollOnce);
    });

    try {
      final result = await completer.future.timeout(timeout, onTimeout: () => null);
      return result;
    } finally {
      pollTimer?.cancel();
      removeCaptureDoneListener(socketListener);
    }
  }

  void attachSettings(SettingsProvider settings) {
    _settings = settings;
    _ensureRealtimeConnection();
  }

  String gardenStatus = 'Chưa kết nối server IoT';

  /// Kết quả phân tích AI gần nhất (ảnh / model); rỗng = chưa có.
  String aiAnalysis = '';

  int? currentMoisture;
  int? currentMoistureRaw;
  double? airTemperatureC;
  double? airHumidityPct;
  int? rainPercent;
  int? rainRaw;
  String? latestImageUrl;

  bool shadeOn = false;
  bool pumpOn = true;
  int waterTodayCount = 0;

  bool iotBusy = false;
  String? lastError;

  bool get pumpDisplayOn => pumpOn;

  List<SensorDisplay> get sensorTiles => [
        SensorDisplay(
          name: 'Nhiệt độ',
          valueLabel: airTemperatureC?.toStringAsFixed(1) ?? '—',
          unit: '°C',
        ),
        SensorDisplay(
          name: 'Ẩm đất',
          valueLabel: currentMoisture?.toString() ?? '—',
          unit: '%',
        ),
        SensorDisplay(
          name: 'Ẩm không khí',
          valueLabel: airHumidityPct?.toStringAsFixed(0) ?? '—',
          unit: '%',
        ),
        SensorDisplay(
          name: 'Mưa',
          valueLabel: rainPercent?.toString() ?? '—',
          unit: '%',
        ),
      ];

  void _ensureRealtimeConnection() {
    final rawBase = _settings?.serverUrl.trim().isNotEmpty == true
        ? _settings!.serverUrl.trim()
        : kDefaultIotServerUrl;
    final apiKey = _settings?.apiKey.trim().isNotEmpty == true
        ? _settings!.apiKey.trim()
        : 'a90cfc28468dc7b73eda44573bebb3a6d39981c92f449a9fc3cda4e56e113ce0'; // Default API key from ESP32

    if (rawBase.isEmpty || apiKey.isEmpty) {
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
      _socketBase = null;
      return;
    }

    if (rawBase == _socketBase && _socket != null) {
      return;
    }

    _socket?.disconnect();
    _socket?.dispose();

    final normalizedBase =
        rawBase.startsWith('http://') || rawBase.startsWith('https://')
            ? rawBase
            : 'http://$rawBase';

    final socket = io.io(
      normalizedBase,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setExtraHeaders({'X-API-KEY': apiKey})
          .enableReconnection()
          .setReconnectionAttempts(9999)
          .setReconnectionDelay(1000)
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) async {
      lastError = null;
      gardenStatus = 'Đã kết nối server IoT';
      notifyListeners();
      await _fetchInitialData(normalizedBase, apiKey);
      
    });
    socket.onDisconnect((_) {
      gardenStatus = 'Mất kết nối server IoT';
      notifyListeners();
    });
    socket.onConnectError((error) {
      lastError = 'Socket lỗi: $error';
      notifyListeners();
    });
    socket.onError((error) {
      lastError = 'Socket lỗi: $error';
      notifyListeners();
    });
    socket.on('sensor', (data) {
      final map = _coerceMap(data);
      if (map != null) {
        applyEspPayload(map);
      }
    });
    socket.on('command', (data) {
      final map = _coerceMap(data);
      if (map != null) {
        _applyCommandPayload(map, countWater: false);
      }
    });
    socket.on('relay', (data) {
  if (iotBusy) return; // 🔥 CHẶN socket khi đang bấm nút

  final map = _coerceMap(data);
  if (map == null) return;

  final rows = map['relay_status'];
  _applyRelayStatusRows(rows);
});
    socket.on('camera', (data) {
      final map = _coerceMap(data);
      String? url;
      if (map != null) {
        url = map['url']?.toString();
        url ??= map['image_url']?.toString();
      }
      if (url != null && url.trim().isNotEmpty) {
        latestImageUrl = url.trim();
        notifyListeners();
        _notifyCaptureListeners(latestImageUrl!);
      }
    });
    socket.on('capture-done', (data) {
      final map = _coerceMap(data);
      String? imageUrl;
      if (map != null) {
        imageUrl = map['imageUrl']?.toString();
        imageUrl ??= map['url']?.toString();
        imageUrl ??= map['image_url']?.toString();
      }
      if (imageUrl != null && imageUrl.trim().isNotEmpty) {
        latestImageUrl = imageUrl.trim();
        notifyListeners();
        _notifyCaptureListeners(latestImageUrl!);
      }
    });
    socket.on('image', (data) {
      final map = _coerceMap(data);
      if (map != null) {
        final url = map['url']?.toString();
        if (url != null && url.isNotEmpty) {
          latestImageUrl = url;
          notifyListeners();
        }
      } else if (data is String && data.trim().isNotEmpty) {
        latestImageUrl = data.trim();
        notifyListeners();
      }
    });

    socket.connect();
    _socket = socket;
    _socketBase = rawBase;
  }

  Map<String, dynamic>? _coerceMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  void _applyRelayStatusRows(dynamic rows) {
    if (rows is! List) return;
    for (final item in rows) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['relay_id'];
      final st = _asBool(m['state']);
      if (st == null) continue;
      final rid = id is int ? id : int.tryParse(id?.toString() ?? '');
      if (rid == kRelayIdShade) {
        shadeOn = st;
      } else if (rid == kRelayIdPump) {
        pumpOn = st;
      }
    }
    notifyListeners();
  }

  bool? _asBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'on' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == 'off' || normalized == '0') {
        return false;
      }
    }
    return null;
  }

  int? _toPercent(dynamic value) {
    if (value is! num) return null;
    const minAdc = 0.0;
    const maxAdc = 4095.0;
    final raw = value.toDouble().clamp(minAdc, maxAdc);
    final ratio = (raw - minAdc) / (maxAdc - minAdc);
    final percent = ((1 - ratio) * 100).round();
    if (percent < 0) return 0;
    if (percent > 100) return 100;
    return percent;
  }

  void _applyCommandPayload(
    Map<String, dynamic> json, {
    bool countWater = false,
    bool emit = true,
  }) {
    final action = json['action']?.toString();

    bool? nextPump;
    if (action == 'pump_on') {
      nextPump = true;
    } else if (action == 'pump_off') {
      nextPump = false;
    } else {
      nextPump = _asBool(json['pump']);
    }

    bool? nextCover;
    if (action == 'shade_on') {
      nextCover = true;
    } else if (action == 'shade_off') {
      nextCover = false;
    } else {
      nextCover = _asBool(json['cover'] ?? json['shade']);
    }

    if (nextPump != null) {
      if (countWater && nextPump && !pumpOn) {
        waterTodayCount += 1;
      }
      pumpOn = nextPump;
    }
    if (nextCover != null) {
      shadeOn = nextCover;
    }

    if (emit) notifyListeners();
  }

  void applyEspPayload(Map<String, dynamic> json) {
    final m = json['soil_moisture'] ?? json['current_moisture'] ?? json['soil'];
    if (m is num) {
      currentMoistureRaw = m.round();
      currentMoisture = _toPercent(m);
    }
    final t = json['temperature'] ?? json['air_temp'];
    if (t is num) airTemperatureC = t.toDouble();
    final h = json['humidity'] ?? json['air_humidity'];
    if (h is num) airHumidityPct = h.toDouble();
    final rain = json['rain'];
    if (rain is num) {
      rainRaw = rain.round();
      rainPercent = _toPercent(rain);
    }

    final maybeImage = json['image_url'] ?? json['url'];
    if (maybeImage is String && maybeImage.trim().isNotEmpty) {
      latestImageUrl = maybeImage.trim();
    }

    final st = json['status']?.toString();
    if (st != null && st.isNotEmpty) {
      gardenStatus = (st == 'success' || st == 'ok')
          ? 'Hệ thống hoạt động bình thường'
          : st;
    }
    notifyListeners();
  }

  Future<void> _fetchInitialData(String serverBase, String apiKey) async {
    try {
      final sensorMap = await _esp32.fetchLatestSensor(
        serverBase: serverBase,
        apiKey: apiKey,
      );
      if (sensorMap.isNotEmpty) {
        final payload = _coerceMap(sensorMap['sensor']) ?? sensorMap;
        applyEspPayload(payload);
      }
    } catch (_) {
      // Ignore errors during initial fetch
    }
  }

  void addCaptureDoneListener(void Function(String imageUrl) listener) {
    _captureDoneListeners.add(listener);
  }

  void removeCaptureDoneListener(void Function(String imageUrl) listener) {
    _captureDoneListeners.remove(listener);
  }

  Future<void> requestCapture() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return;
    }
    lastError = null;
    notifyListeners();
    await _esp32.requestCapture(serverBase: base, apiKey: apiKey);
  }

  Future<String?> fetchLatestImage() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return null;
    }

    final imageMap = await _esp32.fetchLatestImage(
      serverBase: base,
      apiKey: apiKey,
    );
    final rawImage = imageMap['image'];
    String? imageUrl;
    if (rawImage is Map) {
      imageUrl = rawImage['url']?.toString();
    } else if (rawImage is String) {
      imageUrl = rawImage;
    }
    imageUrl ??= imageMap['url']?.toString();
    if (imageUrl != null && imageUrl.trim().isNotEmpty) {
      latestImageUrl = imageUrl.trim();
      notifyListeners();
      return latestImageUrl;
    }
    return null;
  }

  void setAiAnalysisFromServer(String line) {
    aiAnalysis = line;
    notifyListeners();
  }

  Future<void> refreshFromEsp32() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key trong Cài đặt';
      notifyListeners();
      return;
    }
    _ensureRealtimeConnection();
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final sensorMap = await _esp32.fetchLatestSensor(
        serverBase: base,
        apiKey: apiKey,
      );
      if (sensorMap.isEmpty) {
        gardenStatus = 'Chưa có dữ liệu cảm biến từ ESP32';
      } else {
        final payload = _coerceMap(sensorMap['sensor']) ?? sensorMap;
        applyEspPayload(payload);
      }

      final imageMap = await _esp32.fetchLatestImage(
        serverBase: base,
        apiKey: apiKey,
      );
      final rawImage = imageMap['image'];
      String? imageUrl;
      if (rawImage is Map) {
        imageUrl = rawImage['url']?.toString();
      } else if (rawImage is String) {
        imageUrl = rawImage;
      }
      imageUrl ??= imageMap['url']?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        latestImageUrl = imageUrl;
      }

      try {
        final relayMap = await _esp32.fetchRelayStatus(
          serverBase: base,
          apiKey: apiKey,
        );
        _applyRelayStatusRows(relayMap['relay_status']);
      } catch (_) {
        /* relay poll optional — socket may already sync */
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  Future<void> toggleShade() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return;
    }
    final previousShade = shadeOn;
    final next = !shadeOn;
    shadeOn = next;
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(
        serverBase: base,
        apiKey: apiKey,
        action: next ? 'shade_on' : 'shade_off',
      );
      final command = _coerceMap(map['command']);
      if (command != null) {
        _applyCommandPayload(command, emit: false);
      }
      _applyRelayStatusRows(map['relay_status']);
      final sensor = _coerceMap(map['sensor']);
      if (sensor != null) {
        applyEspPayload(sensor);
      }
    } catch (e) {
      shadeOn = previousShade;
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  Future<void> openShade() async {
    await _controlShade(true);
  }

  Future<void> closeShade() async {
    await _controlShade(false);
  }

  Future<void> _controlShade(bool open) async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return;
    }
    final previousShade = shadeOn;
    shadeOn = open;
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(
        serverBase: base,
        apiKey: apiKey,
        action: open ? 'shade_on' : 'shade_off',
      );
      final command = _coerceMap(map['command']);
      if (command != null) {
        _applyCommandPayload(command, emit: false);
      }
      _applyRelayStatusRows(map['relay_status']);
      final sensor = _coerceMap(map['sensor']);
      if (sensor != null) {
        applyEspPayload(sensor);
      }
    } catch (e) {
      shadeOn = previousShade;
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  Future<void> togglePump() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return;
    }
    final previousPump = pumpOn;
    final next = !pumpOn;
    pumpOn = next;
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(
        serverBase: base,
        apiKey: apiKey,
        action: next ? 'pump_on' : 'pump_off',
      );
      final command = _coerceMap(map['command']);
      if (command != null) {
        _applyCommandPayload(command, countWater: true, emit: false);
      }
      _applyRelayStatusRows(map['relay_status']);
      final sensor = _coerceMap(map['sensor']);
      if (sensor != null) {
        applyEspPayload(sensor);
      }
    } catch (e) {
      pumpOn = previousPump;
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _esp32.close();
    super.dispose();
  }
}

class _CameraSnapshot {
  _CameraSnapshot({
    required this.id,
    required this.capturedAt,
    required this.url,
  });

  final dynamic id;
  final String? capturedAt;
  final String url;
}
