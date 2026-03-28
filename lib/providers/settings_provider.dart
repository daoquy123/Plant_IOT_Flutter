import 'package:flutter/foundation.dart';

import '../data/preference_keys.dart';
import '../data/preferences_service.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({PreferencesService? preferences})
      : _preferences = preferences ?? PreferencesService();

  final PreferencesService _preferences;

  String esp32Ip = '';
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
    esp32Ip = map[PreferenceKeys.esp32Ip] as String? ?? '';
    cameraUrl = map[PreferenceKeys.cameraUrl] as String? ?? '';
    aiServerUrl = map[PreferenceKeys.aiServerUrl] as String? ?? '';
    autoWater = map[PreferenceKeys.autoWater] as bool? ?? false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveAll() async {
    await _preferences.saveConnectionConfig(
      esp32Ip: esp32Ip.trim(),
      cameraUrl: cameraUrl.trim(),
      aiServerUrl: aiServerUrl.trim(),
      autoWater: autoWater,
    );
    notifyListeners();
  }

  void setEsp32Ip(String v) {
    esp32Ip = v;
    notifyListeners();
  }

  void setCameraUrl(String v) {
    cameraUrl = v;
    notifyListeners();
  }

  void setAiServerUrl(String v) {
    aiServerUrl = v;
    notifyListeners();
  }

  void setAutoWater(bool v) {
    autoWater = v;
    notifyListeners();
  }
}
