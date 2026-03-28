import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/ai_predict_client.dart';
import '../data/chat_database.dart';
import '../models/chat_message.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    ChatDatabase? database,
    AiPredictClient? aiClient,
    ImagePicker? picker,
  })  : _db = database ?? ChatDatabase(),
        _ai = aiClient ?? AiPredictClient(),
        _picker = picker ?? ImagePicker();

  final ChatDatabase _db;
  final AiPredictClient _ai;
  final ImagePicker _picker;
  SettingsProvider? _settings;

  final List<ChatMessage> messages = [];
  bool loadingHistory = true;
  bool sending = false;
  String? lastError;

  static const suggestions = <String>[
    'Kiểm tra sức khỏe cây',
    'Dự báo thu hoạch',
    'Gợi ý lịch tưới',
    'Nhận diện sâu bệnh qua ảnh',
  ];

  void attachSettings(SettingsProvider settings) {
    _settings = settings;
  }

  Future<void> loadHistory() async {
    loadingHistory = true;
    notifyListeners();
    try {
      final list = await _db.loadMessages();
      messages
        ..clear()
        ..addAll(list);
    } catch (e) {
      lastError = e.toString();
    } finally {
      loadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> sendUserText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    sending = true;
    lastError = null;
    notifyListeners();
    try {
      final row = await _db.insertMessage(text: t, senderType: SenderType.user);
      messages.add(row);
      notifyListeners();

      final reply = await _mockOrForwardToAi(t);
      final aiRow = await _db.insertMessage(
        text: reply,
        senderType: SenderType.ai,
      );
      messages.add(aiRow);
    } catch (e) {
      lastError = e.toString();
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  /// Gửi ảnh lên predict-api; chèn tin nhắn user + phản hồi AI vào thread duy nhất.
  /// Trả về nội dung phân tích khi thành công (để đồng bộ tình trạng cây).
  Future<String?> pickImageAndPredict() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return null;

    final endpoint = _settings?.predictEndpoint ?? '';
    if (endpoint.isEmpty) {
      lastError = 'Chưa cấu hình URL AI Server';
      notifyListeners();
      return null;
    }

    sending = true;
    lastError = null;
    notifyListeners();

    try {
      final userRow = await _db.insertMessage(
        text: '[Ảnh đính kèm]',
        senderType: SenderType.user,
        localImagePath: file.path,
      );
      messages.add(userRow);
      notifyListeners();

      final map = await _ai.predictImageFile(
        predictEndpoint: endpoint,
        imageFile: File(file.path),
      );
      final reply = formatPredictReply(map);
      final aiRow = await _db.insertMessage(
        text: reply,
        senderType: SenderType.ai,
      );
      messages.add(aiRow);
      return reply;
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  static String formatPredictReply(Map<String, dynamic> json) {
    final label = json['label'] ??
        json['prediction'] ??
        json['disease'] ??
        json['class'] ??
        json['result'];
    final conf = json['confidence'] ?? json['score'] ?? json['prob'];
    if (label != null && conf is num) {
      final pct = (conf <= 1 ? conf * 100 : conf).clamp(0, 100).round();
      return 'Phát hiện $label — $pct%';
    }
    if (label != null) return label.toString();
    return json['message']?.toString() ?? json.toString();
  }

  /// Khi bạn có API chat thật, thay nội dung hàm này bằng HTTP tới server.
  Future<String> _mockOrForwardToAi(String userText) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return 'Smart Garden (demo): bạn đã gửi "$userText". '
        'Kết nối endpoint chat thật trong `ChatProvider._mockOrForwardToAi`.';
  }

  @override
  void dispose() {
    _ai.close();
    super.dispose();
  }
}
