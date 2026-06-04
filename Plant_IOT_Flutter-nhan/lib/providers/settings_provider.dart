import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/server_defaults.dart';
import '../data/preference_keys.dart';
import '../data/preferences_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({PreferencesService? preferences})
      : _preferences = preferences ?? PreferencesService();

  final PreferencesService _preferences;

  String serverUrl = '';
  String apiKey = '';
  String cameraUrl = '';
  String aiServerUrl = '';
  bool autoWater = false;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Endpoint đầy đủ cho predict (AI base + `/predict` nếu base không có path).
  String get predictEndpoint {
    final base = aiServerUrl.trim();
    if (base.isEmpty) return '';
    if (base.contains('/')) {
      final uri = Uri.tryParse(base);
      if (uri != null && uri.pathSegments.isNotEmpty) return base;
    }
    final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$normalized/predict';
  }

  Future<void> load() async {
    final map = await _preferences.loadConnectionConfig();
    serverUrl = map[PreferenceKeys.serverUrl] as String? ?? '';
    apiKey = map[PreferenceKeys.apiKey] as String? ?? '';
    cameraUrl = map[PreferenceKeys.cameraUrl] as String? ?? '';
    aiServerUrl = map[PreferenceKeys.aiServerUrl] as String? ?? '';
    autoWater = map[PreferenceKeys.autoWater] as bool? ?? false;
    await _syncFromServerEnv();
    _loaded = true;
    notifyListeners();
  }

  /// Đọc PUBLIC_SERVER_URL, AI_SERVER_URL từ server `.env` (GET /api/config).
  Future<void> _syncFromServerEnv() async {
    final base = serverUrl.trim().isNotEmpty ? serverUrl.trim() : kDefaultIotServerUrl;
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
      if (aiUrl.isNotEmpty && aiUrl != aiServerUrl) {
        aiServerUrl = aiUrl;
        changed = true;
      }
      if (camUrl.isNotEmpty && camUrl != cameraUrl) {
        cameraUrl = camUrl;
        changed = true;
      }
      if (changed) {
        await _preferences.saveConnectionConfig(
          serverUrl: serverUrl.trim(),
          apiKey: apiKey.trim(),
          cameraUrl: cameraUrl.trim(),
          aiServerUrl: aiServerUrl.trim(),
          autoWater: autoWater,
        );
      }
    } catch (_) {
      // Giữ giá trị local nếu server chưa cập nhật /api/config.
    }
  }

  Future<void> saveAll() async {
    await _preferences.saveConnectionConfig(
      serverUrl: serverUrl.trim(),
      apiKey: apiKey.trim(),
      cameraUrl: cameraUrl.trim(),
      aiServerUrl: aiServerUrl.trim(),
      autoWater: autoWater,
    );
    notifyListeners();
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

  void setAutoWater(bool value) {
    autoWater = value;
    notifyListeners();
  }
}
