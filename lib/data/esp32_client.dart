import 'dart:convert';

import 'package:http/http.dart' as http;

/// Độ chờ HTTP cho mạng không ổn định / đường truyền xa.
const Duration _httpTimeout = Duration(seconds: 30);

/// Client HTTP nhỏ gọn để kết nối với backend Node.js của Plant IoT.
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

  Map<String, String> _buildHeaders(String apiKey) {
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (apiKey.trim().isNotEmpty) {
      headers['X-API-KEY'] = apiKey.trim();
    }
    return headers;
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
    required String serverBase,
    required String action,
    required String apiKey,
    Map<String, dynamic>? extra,
  }) async {
    final uri = _resolveBase(serverBase, '/api/relay');
    final body = jsonEncode({
      'action': action,
      if (extra != null) ...extra,
    });
    final response = await _client
        .post(
          uri,
          headers: _buildHeaders(apiKey),
          body: body,
        )
        .timeout(_httpTimeout);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> fetchLatestSensor({
    required String serverBase,
    required String apiKey,
  }) async {
    final uri = _resolveBase(serverBase, '/api/sensors/latest');
    final response = await _client
        .get(uri, headers: _buildHeaders(apiKey))
        .timeout(_httpTimeout);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> fetchLatestImage({
    required String serverBase,
    required String apiKey,
  }) async {
    final uri = _resolveBase(serverBase, '/api/camera/latest');
    final response = await _client
        .get(uri, headers: _buildHeaders(apiKey))
        .timeout(_httpTimeout);
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> fetchRelayStatus({
    required String serverBase,
    required String apiKey,
  }) async {
    final uri = _resolveBase(serverBase, '/api/relay/status');
    final response = await _client
        .get(uri, headers: _buildHeaders(apiKey))
        .timeout(_httpTimeout);
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
