import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/server_defaults.dart';
import '../data/esp32_client.dart';
import '../utils/network_error_message.dart';
import '../models/growing_cycle.dart';
import '../models/sensor_display.dart';
import 'settings_provider.dart';

/// Trạng thái chung cho Dashboard và Điều khiển — đồng bộ qua server Node.js.
class GardenProvider extends ChangeNotifier {
  GardenProvider({Esp32Client? esp32}) : _esp32 = esp32 ?? Esp32Client();

  final Esp32Client _esp32;
  final String _cameraStreamViewerId =
      'flutter-${DateTime.now().microsecondsSinceEpoch}';
  static const Duration _staleFrameThreshold = Duration(seconds: 5);
  static const Duration _cameraWatchdogInterval = Duration(seconds: 3);
  static const Duration _minStreamRestartGap = Duration(seconds: 3);
  SettingsProvider? _settings;
  Timer? _cameraStreamWatchdog;
  bool _wantCameraStream = false;
  int _cameraStreamFps = 8;
  bool _streamRestartInFlight = false;
  DateTime? _lastStreamRestartAt;

  io.Socket? _socket;
  String? _socketBase;
  final List<void Function(String imageUrl)> _captureDoneListeners = [];

  void _notifyCaptureListeners(String url) {
    final u = url.trim();
    if (u.isEmpty) return;
    for (final listener
        in List<void Function(String imageUrl)>.from(_captureDoneListeners)) {
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
      final map =
          await _esp32.fetchLatestImage(serverBase: base, apiKey: apiKey);
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
        return !t
            .isBefore(requestStartedAt.subtract(const Duration(seconds: 3)));
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
      final result =
          await completer.future.timeout(timeout, onTimeout: () => null);
      return result;
    } finally {
      pollTimer.cancel();
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
  Uint8List? latestFrameBytes;
  DateTime? latestFrameAt;
  bool cameraStreamActive = false;

  bool shadeOn = false;
  bool pumpOn = false;
  bool _manualPumpSessionActive = false;
  bool _legacyPumpOffPending = false;
  int waterTodayCount = 0;
  int wateringSessionsPerDay = 2;
  bool wateringBoostActive = false;
  /// Tăng mỗi khi đồng bộ lại số lần bơm — Biểu đồ listen để reload.
  int pumpStatsRevision = 0;
  Timer? _pumpStatsRefreshTimer;

  GrowingCycle? activeGrowingCycle;
  bool cycleBusy = false;

  bool iotBusy = false;
  String? lastError;

  bool get manualPumpSessionActive => _manualPumpSessionActive;
  bool get pumpInSession => _manualPumpSessionActive;
  bool get pumpDisplayOn => _manualPumpSessionActive;

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
      if (_wantCameraStream) {
        await _restartCameraStream();
      }
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
      if (iotBusy) return;
      final map = _coerceMap(data);
      if (map == null) return;

      final rows = map['relay_status'];
      // Tưới tự động (pump_on → chờ → pump_off) không đè nút bơm thủ công.
      _applyRelayStatusRows(rows, ignorePumpIfTriggeredBy: 'auto_water');
      if (_relayStatusIncludesPumpTrigger(rows, 'auto_water')) {
        _schedulePumpStatsRefresh();
      }
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
    socket.on('camera-frame', (data) {
      final bytes = _coerceFrameBytes(data);
      if (bytes == null || bytes.isEmpty) return;
      latestFrameBytes = bytes;
      latestFrameAt = DateTime.now();
      cameraStreamActive = true;
      notifyListeners();
    });
    socket.on('camera-stream-status', (data) {
      final map = _coerceMap(data);
      final enabled = map == null ? null : _asBool(map['enabled']);
      if (enabled != null) {
        cameraStreamActive = enabled;
        if (!enabled) {
          latestFrameBytes = null;
          latestFrameAt = null;
        }
        notifyListeners();
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

  Uint8List? _coerceFrameBytes(dynamic data) {
    dynamic raw = data;
    if (data is Map) {
      raw = data['image'] ?? data['bytes'] ?? data['frame'];
    }
    if (raw is Uint8List) return raw;
    if (raw is List) {
      final bytes = <int>[];
      for (final value in raw) {
        if (value is int) {
          bytes.add(value);
        } else if (value is num) {
          bytes.add(value.toInt());
        } else {
          return null;
        }
      }
      return Uint8List.fromList(bytes);
    }
    return null;
  }

  bool _relayStatusIncludesPumpTrigger(dynamic rows, String triggeredBy) {
    if (rows is! List) return false;
    for (final item in rows) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['relay_id'];
      final rid = id is int ? id : int.tryParse(id?.toString() ?? '');
      if (rid != kRelayIdPump) continue;
      if (m['triggered_by']?.toString() == triggeredBy) return true;
    }
    return false;
  }

  void _applyRelayStatusRows(
    dynamic rows, {
    String? ignorePumpIfTriggeredBy,
  }) {
    if (rows is! List) return;
    var changed = false;
    for (final item in rows) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final id = m['relay_id'];
      final st = _asBool(m['state']);
      if (st == null) continue;
      final rid = id is int ? id : int.tryParse(id?.toString() ?? '');
      if (rid == kRelayIdShade) {
        if (shadeOn != st) {
          shadeOn = st;
          changed = true;
        }
      } else if (rid == kRelayIdPump) {
        final trigger = m['triggered_by']?.toString() ?? '';
        if (ignorePumpIfTriggeredBy != null && trigger == ignorePumpIfTriggeredBy) {
          continue;
        }
        if (_manualPumpSessionActive) {
          continue;
        }
        if (pumpOn != st) {
          pumpOn = st;
          changed = true;
        }
      }
    }
    if (changed) notifyListeners();
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

  /// Nhãn ngày VN (dd/MM) — khớp API analytics 7d.
  static String vnTodayLabel() {
    final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final d = vn.day.toString().padLeft(2, '0');
    final m = vn.month.toString().padLeft(2, '0');
    return '$d/$m';
  }

  /// Debounce — gọi sau phiên bơm (tự động / socket).
  void _schedulePumpStatsRefresh() {
    _pumpStatsRefreshTimer?.cancel();
    _pumpStatsRefreshTimer = Timer(const Duration(milliseconds: 800), () {
      unawaited(refreshWaterTodayCount());
    });
  }

  /// Lịch tưới đề xuất từ server (2 hoặc 3 lần/ngày khi ẩm đất TB thấp).
  Future<void> refreshWateringPlan() async {
    final base = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (base.isEmpty || apiKey.isEmpty) return;

    try {
      final map = await _esp32.fetchWateringPlan(
        serverBase: base,
        apiKey: apiKey,
      );
      final sessions = map['sessionsPerDay'];
      final boost = map['boostActive'] == true;
      final newSessions = sessions is num ? sessions.round() : 2;
      if (newSessions != wateringSessionsPerDay ||
          boost != wateringBoostActive) {
        wateringSessionsPerDay = newSessions.clamp(2, 3);
        wateringBoostActive = boost;
        notifyListeners();
      }
    } catch (_) {
      // Giữ giá trị local nếu API lỗi.
    }
  }

  /// Đồng bộ số lần bơm hôm nay từ `pump_runs` trên server (giống tab Biểu đồ).
  Future<void> refreshWaterTodayCount() async {
    final base = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (base.isEmpty || apiKey.isEmpty) return;

    try {
      final map = await _esp32.fetchAnalytics(
        serverBase: base,
        apiKey: apiKey,
        range: '7d',
      );
      final rows = map['buckets'];
      if (rows is! List) return;
      final today = vnTodayLabel();
      var newCount = 0;
      var found = false;
      for (final raw in rows) {
        if (raw is! Map) continue;
        final row = Map<String, dynamic>.from(raw);
        if (row['label']?.toString() != today) continue;
        found = true;
        final count = row['pump_count'];
        if (count is num) {
          newCount = count.round();
        } else {
          newCount = int.tryParse(count?.toString() ?? '') ?? 0;
        }
        break;
      }
      if (!found) {
        newCount = 0;
      }
      if (newCount != waterTodayCount) {
        waterTodayCount = newCount;
        pumpStatsRevision += 1;
        notifyListeners();
      }
    } catch (_) {
      // Giữ giá trị local nếu API lỗi.
    }
  }

  void _applyCommandPayload(
    Map<String, dynamic> json, {
    bool countWater = false,
    bool? pumpWasOnBefore,
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
      final wasOn = pumpWasOnBefore ?? pumpOn;
      if (countWater && nextPump && !wasOn) {
        waterTodayCount += 1;
      }
      if (!_manualPumpSessionActive && !nextPump) {
        pumpOn = nextPump;
      }
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
      await refreshWaterTodayCount();
      await refreshActiveGrowingCycle();
    } catch (_) {
      // Ignore errors during initial fetch
    }
  }

  Future<void> refreshActiveGrowingCycle() async {
    final base = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (base.isEmpty || apiKey.isEmpty) return;

    try {
      final map = await _esp32.fetchActiveGrowingCycle(
        serverBase: base,
        apiKey: apiKey,
      );
      final raw = map['cycle'];
      activeGrowingCycle = raw is Map
          ? GrowingCycle.fromJson(Map<String, dynamic>.from(raw))
          : null;
      notifyListeners();
    } catch (_) {
      // Giữ trạng thái cũ nếu lỗi mạng.
    }
  }

  static String toIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<bool> startGrowingCycle(DateTime startDate, {String? note}) async {
    final base = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return false;
    }

    cycleBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.startGrowingCycle(
        serverBase: base,
        apiKey: apiKey,
        startedAtIsoDate: toIsoDate(startDate),
        note: note,
      );
      final raw = map['cycle'];
      if (raw is! Map) {
        lastError = 'Server không trả chu kỳ hợp lệ';
        return false;
      }
      activeGrowingCycle =
          GrowingCycle.fromJson(Map<String, dynamic>.from(raw));
      return true;
    } catch (e) {
      lastError = friendlyNetworkError(
        e,
        serverUrl: base,
      );
      return false;
    } finally {
      cycleBusy = false;
      notifyListeners();
    }
  }

  Future<bool> endActiveGrowingCycle() async {
    final cycle = activeGrowingCycle;
    if (cycle == null || !cycle.isActive) return false;

    final base = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return false;
    }

    cycleBusy = true;
    lastError = null;
    notifyListeners();
    try {
      await _esp32.endGrowingCycle(
        serverBase: base,
        apiKey: apiKey,
        cycleId: cycle.id,
      );
      activeGrowingCycle = null;
      return true;
    } catch (e) {
      lastError = friendlyNetworkError(
        e,
        serverUrl: base,
      );
      return false;
    } finally {
      cycleBusy = false;
      notifyListeners();
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

  void _startCameraStreamWatchdog() {
    _cameraStreamWatchdog?.cancel();
    _cameraStreamWatchdog = Timer.periodic(
      _cameraWatchdogInterval,
      (_) => unawaited(_checkCameraStreamHealth()),
    );
  }

  void _stopCameraStreamWatchdog() {
    _cameraStreamWatchdog?.cancel();
    _cameraStreamWatchdog = null;
  }

  Future<void> _checkCameraStreamHealth() async {
    if (!_wantCameraStream) return;
    final frameAt = latestFrameAt;
    final stale = frameAt == null ||
        DateTime.now().difference(frameAt) > _staleFrameThreshold;
    if (!stale) return;
    await _restartCameraStream();
  }

  Future<void> _restartCameraStream() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) return;
    if (_streamRestartInFlight) return;
    final now = DateTime.now();
    if (_lastStreamRestartAt != null &&
        now.difference(_lastStreamRestartAt!) < _minStreamRestartGap) {
      return;
    }

    _streamRestartInFlight = true;
    _lastStreamRestartAt = now;
    _ensureRealtimeConnection();
    try {
      await _esp32.startCameraStream(
        serverBase: base,
        apiKey: apiKey,
        viewerId: _cameraStreamViewerId,
        fps: _cameraStreamFps,
      );
      cameraStreamActive = true;
      lastError = null;
      notifyListeners();
    } catch (e) {
      lastError = friendlyNetworkError(e, serverUrl: base);
      notifyListeners();
    } finally {
      _streamRestartInFlight = false;
    }
  }

  Future<void> startCameraStream({int fps = 8}) async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return;
    }
    _wantCameraStream = true;
    _cameraStreamFps = fps;
    _startCameraStreamWatchdog();
    await _restartCameraStream();
  }

  Future<void> stopCameraStream() async {
    _wantCameraStream = false;
    _stopCameraStreamWatchdog();
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) return;
    try {
      await _esp32.stopCameraStream(
        serverBase: base,
        apiKey: apiKey,
        viewerId: _cameraStreamViewerId,
      );
    } catch (_) {
      // Leaving Dashboard should not surface a noisy stop-stream error.
    } finally {
      cameraStreamActive = false;
      latestFrameBytes = null;
      latestFrameAt = null;
      notifyListeners();
    }
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

      try {
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
      } on Esp32HttpException catch (e) {
        if (e.statusCode != 404) rethrow;
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

  void _resetManualPumpSessionFlags() {
    _manualPumpSessionActive = false;
    _legacyPumpOffPending = false;
    pumpOn = false;
  }

  Future<void> _sendPumpOffIfNeeded() async {
    if (!_legacyPumpOffPending) return;
    _legacyPumpOffPending = false;

    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) return;

    try {
      await _esp32.postAction(
        serverBase: base,
        apiKey: apiKey,
        action: 'pump_off',
      );
    } catch (_) {
      // Server pump_start path tự tắt — bỏ qua lỗi pump_off legacy.
    }
  }

  /// Gọi khi hết phiên tưới trên UI hoặc hủy phiên.
  Future<void> completePumpSession({bool cancelled = false}) async {
    if (!_manualPumpSessionActive && !_legacyPumpOffPending) return;

    _resetManualPumpSessionFlags();
    notifyListeners();

    if (!cancelled) {
      await _sendPumpOffIfNeeded();
      await refreshWaterTodayCount();
    }
  }

  /// Bắt đầu phiên tưới trên server (UI đếm ngược riêng ở ControlScreen).
  Future<bool> startPumpSession() async {
    final base = _settings?.serverUrl ?? '';
    final apiKey = _settings?.apiKey ?? '';
    if (base.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key';
      notifyListeners();
      return false;
    }
    if (_manualPumpSessionActive) return false;

    _manualPumpSessionActive = true;
    pumpOn = true;
    lastError = null;
    notifyListeners();

    try {
      await _esp32.postAction(
        serverBase: base,
        apiKey: apiKey,
        action: 'pump_start',
        extra: {'duration_seconds': kPumpSessionSeconds},
      );
      unawaited(refreshWaterTodayCount());
      return true;
    } on Esp32HttpException catch (e) {
      if (e.statusCode == 409) {
        _resetManualPumpSessionFlags();
        lastError = 'Máy bơm đang trong phiên tưới. Vui lòng đợi hết phiên.';
        notifyListeners();
        return false;
      }
      if (e.statusCode == 400 || e.statusCode == 404) {
        try {
          await _esp32.postAction(
            serverBase: base,
            apiKey: apiKey,
            action: 'pump_on',
          );
          _legacyPumpOffPending = true;
          unawaited(refreshWaterTodayCount());
          return true;
        } catch (e2) {
          _resetManualPumpSessionFlags();
          lastError = e2.toString();
          notifyListeners();
          return false;
        }
      }
      _resetManualPumpSessionFlags();
      lastError = e.toString();
      notifyListeners();
      return false;
    } catch (e) {
      _resetManualPumpSessionFlags();
      lastError = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _pumpStatsRefreshTimer?.cancel();
    _stopCameraStreamWatchdog();
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
