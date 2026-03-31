import 'dart:convert';

import 'package:http/http.dart' as http;

/// Flutter gọi server Node.js, server sẽ chuyển tiếp tới ESP32 / ESP32-CAM.
class Esp32Client {
  Esp32Client({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _resolveBase(String raw, [String endpoint = '']) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw StateError('Chưa cấu hình URL server Node.js');
    }
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
            ? trimmed
            : 'http://$trimmed';
    final base = Uri.parse(withScheme);
    return endpoint.isEmpty ? base : base.resolve(endpoint);
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final raw = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Esp32HttpException(response.statusCode, raw);
    }
    if (raw.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Server không trả JSON object hợp lệ');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> postAction({
    required String esp32Base,
    required String action,
    Map<String, dynamic>? extra,
  }) async {
    final uri = _resolveBase(esp32Base, '/api/relay');
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
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> fetchLatestSensor({
    required String esp32Base,
  }) async {
    final uri = _resolveBase(esp32Base, '/api/sensor/latest');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> fetchLatestImage({
    required String esp32Base,
  }) async {
    final uri = _resolveBase(esp32Base, '/api/image/latest');
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 15));
    return _decodeMap(response);
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
