import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Ảnh → multipart → AI server (VGG16 / predict-api). Tuỳ backend của bạn chỉnh field name.
class AiPredictClient {
  AiPredictClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// [predictEndpoint] ví dụ: `http://192.168.1.10:8000/predict` hoặc full path bạn đặt.
  Future<Map<String, dynamic>> predictImageFile({
    required String predictEndpoint,
    required File imageFile,
    String fileField = 'file',
  }) async {
    final uri = Uri.parse(predictEndpoint.trim());
    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath(fileField, imageFile.path),
    );

    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 60),
        );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiPredictException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI server không trả JSON object');
    }
    return decoded;
  }

  void close() => _client.close();
}

class AiPredictException implements Exception {
  AiPredictException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'AiPredictException($statusCode): $body';
}
