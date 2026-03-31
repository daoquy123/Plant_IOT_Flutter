import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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
  bool pumpOn = false;
  bool pumpManuallyActivated = false;
  int waterTodayCount = 0;

  bool iotBusy = false;
  String? lastError;

  bool get pumpDisplayOn => pumpManuallyActivated && pumpOn;

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
    final rawBase = _settings?.esp32Ip.trim() ?? '';
    if (rawBase.isEmpty) {
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
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      lastError = null;
      gardenStatus = 'Đã kết nối server IoT';
      notifyListeners();
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
    final m = json['current_moisture'] ?? json['soil'];
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

  void setAiAnalysisFromServer(String line) {
    aiAnalysis = line;
    notifyListeners();
  }

  Future<void> refreshFromEsp32() async {
    final base = _settings?.esp32Ip ?? '';
    if (base.isEmpty) {
      lastError = 'Thiếu URL server Node.js trong Cài đặt';
      notifyListeners();
      return;
    }
    _ensureRealtimeConnection();
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final sensorMap = await _esp32.fetchLatestSensor(esp32Base: base);
      if (sensorMap.isEmpty) {
        gardenStatus = 'Chưa có dữ liệu cảm biến từ ESP32';
      } else {
        final payload = _coerceMap(sensorMap['sensor']) ?? sensorMap;
        applyEspPayload(payload);
      }

      final imageMap = await _esp32.fetchLatestImage(esp32Base: base);
      final imageUrl = imageMap['url']?.toString();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        latestImageUrl = imageUrl;
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  Future<void> toggleShade() async {
    final base = _settings?.esp32Ip ?? '';
    if (base.isEmpty) {
      lastError = 'Thiếu URL server Node.js';
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
        esp32Base: base,
        action: next ? 'shade_on' : 'shade_off',
      );
      final command =
          _coerceMap(map['command']) ?? <String, dynamic>{'cover': next};
      _applyCommandPayload(command, emit: false);
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
    final base = _settings?.esp32Ip ?? '';
    if (base.isEmpty) {
      lastError = 'Thiếu URL server Node.js';
      notifyListeners();
      return;
    }
    final previousPump = pumpOn;
    final previousManual = pumpManuallyActivated;
    final next = !pumpDisplayOn;
    pumpManuallyActivated = true;
    pumpOn = next;
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(
        esp32Base: base,
        action: next ? 'pump_on' : 'pump_off',
      );
      final command =
          _coerceMap(map['command']) ?? <String, dynamic>{'pump': next};
      _applyCommandPayload(command, countWater: true, emit: false);
      final sensor = _coerceMap(map['sensor']);
      if (sensor != null) {
        applyEspPayload(sensor);
      }
    } catch (e) {
      pumpOn = previousPump;
      pumpManuallyActivated = previousManual;
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
