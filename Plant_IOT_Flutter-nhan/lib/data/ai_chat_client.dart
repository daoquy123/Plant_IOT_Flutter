import 'dart:convert';

import 'package:http/http.dart' as http;

/// Gửi tin nhắn tới FastAPI `/api/chat` (Qwen qua Ollama hoặc API tương thích).
class AiChatClient {
  AiChatClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> sendMessage({
    required String chatEndpoint,
    required String message,
    List<ChatHistoryEntry> history = const [],
  }) async {
    final body = jsonEncode({
      'message': message,
      'history': history
          .map((e) => {'role': e.role, 'content': e.content})
          .toList(),
    });
    final headers = {'Content-Type': 'application/json; charset=utf-8'};
    final endpoints = _chatEndpointCandidates(chatEndpoint.trim());
    http.Response? response;
    for (final uri in endpoints) {
      response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 404) break;
    }
    response ??= await _client
        .post(
          Uri.parse(chatEndpoint.trim()),
          headers: headers,
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiChatException(response.statusCode, response.body);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI chat không trả JSON object');
    }
    final reply = decoded['reply']?.toString().trim();
    if (reply == null || reply.isEmpty) {
      throw FormatException(
        'Phản hồi thiếu trường reply: ${decoded.toString()}',
      );
    }
    return reply;
  }

  List<Uri> _chatEndpointCandidates(String endpoint) {
    final primary = Uri.parse(endpoint);
    final candidates = <Uri>[primary];
    final path = primary.path;
    if (path.endsWith('/api/chat')) {
      final alt = primary.replace(path: path.replaceFirst('/api/chat', '/chat'));
      if (alt != primary) candidates.add(alt);
    } else if (!path.endsWith('/chat')) {
      final base = endpoint.endsWith('/')
          ? endpoint.substring(0, endpoint.length - 1)
          : endpoint;
      candidates.add(Uri.parse('$base/chat'));
    }
    return candidates;
  }

  void close() => _client.close();
}

class ChatHistoryEntry {
  const ChatHistoryEntry({required this.role, required this.content});

  final String role;
  final String content;
}

class AiChatException implements Exception {
  AiChatException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  String get message {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {}
    return body;
  }

  @override
  String toString() => 'AiChatException($statusCode): $message';
}
