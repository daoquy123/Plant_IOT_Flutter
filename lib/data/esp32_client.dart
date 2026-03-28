import 'dart:convert';

import 'package:http/http.dart' as http;

/// Gửi `{ "action": "pump_on" }` tới ESP32, parse `{ "status", "current_moisture" }`.
class Esp32Client {
  Esp32Client({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _resolveBase(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw StateError('Chưa cấu hình IP ESP32');
    }
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'http://$trimmed';
    return Uri.parse(withScheme);
  }

  Future<Map<String, dynamic>> postAction({
    required String esp32Base,
    required String action,
    Map<String, dynamic>? extra,
  }) async {
    final uri = _resolveBase(esp32Base);
    final body = jsonEncode({
      'action': action,
      if (extra != null) ...extra,
    });
    final response = await _client
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: body,
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Esp32HttpException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ESP32 không trả JSON object');
    }
    return decoded;
  }

  void close() => _client.close();
}

class Esp32HttpException implements Exception {
  Esp32HttpException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'Esp32HttpException($statusCode): $body';
}
