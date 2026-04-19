import 'package:shared_preferences/shared_preferences.dart';

import '../config/server_defaults.dart';
import 'preference_keys.dart';

class PreferencesService {
  Future<SharedPreferences> get _p async => SharedPreferences.getInstance();

  Future<String?> getString(String key) async {
    final prefs = await _p;
    return prefs.getString(key);
  }

  Future<void> setString(String key, String value) async {
    final prefs = await _p;
    await prefs.setString(key, value);
  }

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final prefs = await _p;
    return prefs.getBool(key) ?? defaultValue;
  }

  Future<void> setBool(String key, bool value) async {
    final prefs = await _p;
    await prefs.setBool(key, value);
  }

  Future<Map<String, dynamic>> loadConnectionConfig() async {
    final prefs = await _p;
    return {
      PreferenceKeys.serverUrl: prefs.getString(PreferenceKeys.serverUrl) ??
          prefs.getString(PreferenceKeys.esp32Ip) ??
          kDefaultIotServerUrl,
      PreferenceKeys.apiKey: prefs.getString(PreferenceKeys.apiKey) ?? '',
      PreferenceKeys.cameraUrl: prefs.getString(PreferenceKeys.cameraUrl) ?? '',
      PreferenceKeys.aiServerUrl:
          prefs.getString(PreferenceKeys.aiServerUrl) ?? '',
      PreferenceKeys.autoWater:
          prefs.getBool(PreferenceKeys.autoWater) ?? false,
    };
  }

  Future<void> saveConnectionConfig({
    required String serverUrl,
    required String apiKey,
    required String cameraUrl,
    required String aiServerUrl,
    required bool autoWater,
  }) async {
    final prefs = await _p;
    await prefs.setString(PreferenceKeys.serverUrl, serverUrl);
    await prefs.setString(PreferenceKeys.apiKey, apiKey);
    await prefs.setString(PreferenceKeys.cameraUrl, cameraUrl);
    await prefs.setString(PreferenceKeys.aiServerUrl, aiServerUrl);
    await prefs.setBool(PreferenceKeys.autoWater, autoWater);
  }
}
