import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/server_defaults.dart';
import '../data/esp32_client.dart';
import '../data/preference_keys.dart';
import '../data/preferences_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({PreferencesService? preferences, Esp32Client? esp32})
      : _preferences = preferences ?? PreferencesService(),
        _esp32 = esp32 ?? Esp32Client();

  final PreferencesService _preferences;
  final Esp32Client _esp32;

  String serverUrl = '';
  String apiKey = '';
  String cameraUrl = '';
  String aiServerUrl = '';
  bool autoWater = false;
  bool sensorAlert = true;
  bool pestAlert = false;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  String get _serverBase =>
      serverUrl.trim().isNotEmpty ? serverUrl.trim() : kDefaultIotServerUrl;

  /// Endpoint đầy đủ cho predict (AI base + `/predict` nếu base không có path).
  String get predictEndpoint {
    final base = aiServerUrl.trim();
    if (base.isEmpty) return '';
    if (base.contains('/')) {
      final uri = Uri.tryParse(base);
      if (uri != null && uri.pathSegments.isNotEmpty) return base;
    }
    final normalized =
        base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalized/predict';
  }

  Future<void> load() async {
    final map = await _preferences.loadConnectionConfig();
    serverUrl = map[PreferenceKeys.serverUrl] as String? ?? '';
    apiKey = map[PreferenceKeys.apiKey] as String? ?? '';
    cameraUrl = map[PreferenceKeys.cameraUrl] as String? ?? '';
    aiServerUrl = map[PreferenceKeys.aiServerUrl] as String? ?? '';
    autoWater = map[PreferenceKeys.autoWater] as bool? ?? false;
    sensorAlert = map[PreferenceKeys.sensorAlert] as bool? ?? true;
    pestAlert = map[PreferenceKeys.pestAlert] as bool? ?? false;
    await _syncFromServerEnv();
    await _syncAutoWaterFromServer();
    await _syncSensorAlertFromServer();
    await _syncPestAlertFromServer();
    _loaded = true;
    notifyListeners();
  }

  /// Đọc PUBLIC_SERVER_URL, AI_SERVER_URL từ server `.env` (GET /api/config).
  Future<void> _syncFromServerEnv() async {
    final base = _serverBase;
    try {
      final uri = Uri.parse(
        base.startsWith('http') ? base : 'http://$base',
      ).resolve('/api/config');
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return;

      final publicUrl = decoded['public_server_url']?.toString().trim() ?? '';
      final aiUrl = decoded['ai_server_url']?.toString().trim() ?? '';
      final camUrl = decoded['camera_url']?.toString().trim() ?? '';

      var changed = false;
      if (publicUrl.isNotEmpty && publicUrl != serverUrl) {
        serverUrl = publicUrl;
        changed = true;
      }
      if (aiUrl.isNotEmpty &&
          aiUrl != aiServerUrl &&
          !_isLocalDevAiUrl(aiServerUrl)) {
        aiServerUrl = aiUrl;
        changed = true;
      }
      if (camUrl.isNotEmpty && camUrl != cameraUrl) {
        cameraUrl = camUrl;
        changed = true;
      }
      if (changed) {
        await _persistLocal();
      }
    } catch (_) {
      // Giữ giá trị local nếu server chưa cập nhật /api/config.
    }
  }

  Future<void> _syncAutoWaterFromServer() async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    try {
      final enabled = await _esp32.fetchAutoWaterEnabled(
        serverBase: _serverBase,
        apiKey: key,
      );
      if (enabled != autoWater) {
        autoWater = enabled;
        await _persistLocal();
      }
    } catch (_) {
      // Server cũ chưa có API — giữ local.
    }
  }

  Future<void> _syncSensorAlertFromServer() async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    try {
      final enabled = await _esp32.fetchSensorAlertEnabled(
        serverBase: _serverBase,
        apiKey: key,
      );
      if (enabled != sensorAlert) {
        sensorAlert = enabled;
        await _persistLocal();
      }
    } catch (_) {}
  }

  Future<void> _syncPestAlertFromServer() async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    try {
      final enabled = await _esp32.fetchPestAlertEnabled(
        serverBase: _serverBase,
        apiKey: key,
      );
      if (enabled != pestAlert) {
        pestAlert = enabled;
        await _persistLocal();
      }
    } catch (_) {}
  }

  Future<void> saveAll() async {
    await _persistLocal();
    await _pushAutoWaterToServer();
    await _pushSensorAlertToServer();
    await _pushPestAlertToServer();
    notifyListeners();
  }

  Future<void> _persistLocal() async {
    await _preferences.saveConnectionConfig(
      serverUrl: serverUrl.trim(),
      apiKey: apiKey.trim(),
      cameraUrl: cameraUrl.trim(),
      aiServerUrl: aiServerUrl.trim(),
      autoWater: autoWater,
      sensorAlert: sensorAlert,
      pestAlert: pestAlert,
    );
  }

  Future<void> _pushSensorAlertToServer() async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    await _esp32.updateSensorAlertEnabled(
      serverBase: _serverBase,
      apiKey: key,
      enabled: sensorAlert,
    );
  }

  Future<void> _pushPestAlertToServer() async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    await _esp32.updatePestAlertEnabled(
      serverBase: _serverBase,
      apiKey: key,
      enabled: pestAlert,
    );
  }

  Future<void> _pushAutoWaterToServer() async {
    final key = apiKey.trim();
    if (key.isEmpty) return;
    await _esp32.updateAutoWaterEnabled(
      serverBase: _serverBase,
      apiKey: key,
      enabled: autoWater,
    );
  }

  Future<void> setAutoWater(bool value) async {
    autoWater = value;
    notifyListeners();
    await _persistLocal();
    final key = apiKey.trim();
    if (key.isEmpty) return;
    try {
      await _esp32.updateAutoWaterEnabled(
        serverBase: _serverBase,
        apiKey: key,
        enabled: value,
      );
    } catch (_) {
      // Giữ local; cron trên server dùng DB khi sync thành công.
    }
  }

  Future<void> setSensorAlert(bool value) async {
    sensorAlert = value;
    notifyListeners();
    await _persistLocal();
    final key = apiKey.trim();
    if (key.isEmpty) return;
    try {
      await _esp32.updateSensorAlertEnabled(
        serverBase: _serverBase,
        apiKey: key,
        enabled: value,
      );
    } catch (_) {}
  }

  Future<void> setPestAlert(bool value) async {
    pestAlert = value;
    notifyListeners();
    await _persistLocal();
    final key = apiKey.trim();
    if (key.isEmpty) return;
    try {
      await _esp32.updatePestAlertEnabled(
        serverBase: _serverBase,
        apiKey: key,
        enabled: value,
      );
    } catch (_) {}
  }

  void setServerUrl(String value) {
    serverUrl = value;
    notifyListeners();
  }

  void setApiKey(String value) {
    apiKey = value;
    notifyListeners();
  }

  void setCameraUrl(String value) {
    cameraUrl = value;
    notifyListeners();
  }

  void setAiServerUrl(String value) {
    aiServerUrl = value;
    notifyListeners();
  }

  /// Giữ URL AI local khi test (127.0.0.1 / emulator), không ghi đè từ VPS.
  static bool _isLocalDevAiUrl(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '10.0.2.2' ||
        host == '0.0.0.0';
  }
}
