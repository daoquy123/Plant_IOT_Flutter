import 'package:flutter/foundation.dart';

import '../data/esp32_client.dart';
import '../models/sensor_display.dart';
import 'settings_provider.dart';

/// Trạng thái chung cho Dashboard (1) và Điều khiển (2) — đồng bộ sau mỗi lệnh ESP32.
class GardenProvider extends ChangeNotifier {
  GardenProvider({Esp32Client? esp32}) : _esp32 = esp32 ?? Esp32Client();

  final Esp32Client _esp32;
  SettingsProvider? _settings;

  void attachSettings(SettingsProvider settings) {
    _settings = settings;
  }

  String gardenStatus = 'Chưa kết nối ESP32';
  /// Kết quả phân tích AI gần nhất (ảnh / model); rỗng = chưa có.
  String aiAnalysis = '';

  int? currentMoisture;
  double? airTemperatureC;
  double? airHumidityPct;
  int? lightLux;

  bool shadeOn = false;
  bool pumpOn = false;
  int waterTodayCount = 0;

  bool iotBusy = false;
  String? lastError;

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
          name: 'Ánh sáng',
          valueLabel: lightLux?.toString() ?? '—',
          unit: 'lux',
        ),
      ];

  void applyEspPayload(Map<String, dynamic> json) {
    final m = json['current_moisture'];
    if (m is num) currentMoisture = m.round();
    final t = json['temperature'] ?? json['air_temp'];
    if (t is num) airTemperatureC = t.toDouble();
    final h = json['humidity'] ?? json['air_humidity'];
    if (h is num) airHumidityPct = h.toDouble();
    final lux = json['light_lux'] ?? json['lux'];
    if (lux is num) lightLux = lux.round();

    final st = json['status']?.toString();
    if (st != null) {
      gardenStatus = st == 'success' ? 'Hệ thống hoạt động bình thường' : st;
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
      lastError = 'Thiếu IP ESP32 trong Cài đặt';
      notifyListeners();
      return;
    }
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(esp32Base: base, action: 'status');
      applyEspPayload(map);
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
      lastError = 'Thiếu IP ESP32';
      notifyListeners();
      return;
    }
    final next = !shadeOn;
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(
        esp32Base: base,
        action: next ? 'shade_on' : 'shade_off',
      );
      shadeOn = next;
      applyEspPayload(map);
    } catch (e) {
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  Future<void> togglePump() async {
    final base = _settings?.esp32Ip ?? '';
    if (base.isEmpty) {
      lastError = 'Thiếu IP ESP32';
      notifyListeners();
      return;
    }
    final next = !pumpOn;
    iotBusy = true;
    lastError = null;
    notifyListeners();
    try {
      final map = await _esp32.postAction(
        esp32Base: base,
        action: next ? 'pump_on' : 'pump_off',
      );
      pumpOn = next;
      if (next) waterTodayCount += 1;
      applyEspPayload(map);
    } catch (e) {
      lastError = e.toString();
    } finally {
      iotBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _esp32.close();
    super.dispose();
  }
}
