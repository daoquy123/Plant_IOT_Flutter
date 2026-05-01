import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Ảnh → multipart → AI server (VGG16 / predict-api). Tuỳ backend của bạn chỉnh field name.
class AiPredictClient {
  AiPredictClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// [predictEndpoint] ví dụ: `http://192.168.1.10:8000/predict` hoặc full path bạn đặt.
  Future<Map<String, dynamic>> predictImageFile({
    required String predictEndpoint,
    required File imageFile,
    String fileField = 'file',
    String? model,
  }) async {
    final uri = Uri.parse(predictEndpoint.trim());
    final request = http.MultipartRequest('POST', uri);
    if (model != null && model.trim().isNotEmpty) {
      request.fields['model'] = model.trim();
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        fileField,
        imageFile.path,
        contentType: _inferImageContentType(imageFile.path),
      ),
    );
    return _sendAndDecode(request);
  }

  Future<Map<String, dynamic>> predictImageBytes({
    required String predictEndpoint,
    required Uint8List bytes,
    String fileField = 'file',
    String filename = 'camera.jpg',
    String? model,
  }) async {
    final uri = Uri.parse(predictEndpoint.trim());
    final request = http.MultipartRequest('POST', uri);
    if (model != null && model.trim().isNotEmpty) {
      request.fields['model'] = model.trim();
    }
    request.files.add(
      http.MultipartFile.fromBytes(
        fileField,
        bytes,
        filename: filename,
        contentType: _inferImageContentType(filename),
      ),
    );
    return _sendAndDecode(request);
  }

  MediaType _inferImageContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    return MediaType('image', 'jpeg');
  }

  Future<Map<String, dynamic>> _sendAndDecode(http.MultipartRequest request) async {
    final streamed = await _client.send(request).timeout(const Duration(seconds: 60));
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