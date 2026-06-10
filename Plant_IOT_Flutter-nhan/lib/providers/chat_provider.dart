import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/ai_predict_client.dart';
import '../data/chat_database.dart';
import '../data/esp32_client.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../utils/conversation_time.dart';
import 'garden_provider.dart';
import 'settings_provider.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    ChatDatabase? database,
    AiPredictClient? aiClient,
    Esp32Client? esp32,
    ImagePicker? picker,
  })  : _db = database ?? ChatDatabase(),
        _ai = aiClient ?? AiPredictClient(),
        _esp32 = esp32 ?? Esp32Client(),
        _picker = picker ?? ImagePicker();

  final ChatDatabase _db;
  final AiPredictClient _ai;
  final Esp32Client _esp32;
  final ImagePicker _picker;
  SettingsProvider? _settings;

  final List<ChatConversation> conversations = [];
  final List<ChatMessage> messages = [];
  int? activeConversationId;
  bool loadingHistory = true;
  bool sending = false;
  String? lastError;

  static const suggestions = <String>[
    'Kiểm tra sức khỏe cây',
    'Dự báo thu hoạch',
    'Gợi ý lịch tưới',
  ];

  static const modelOptions = <String, String>{
    'vgg16': 'VGG16',
    'resnet': 'ResNet',
  };

  ChatConversation? get activeConversation {
    if (activeConversationId == null) return null;
    for (final c in conversations) {
      if (c.id == activeConversationId) return c;
    }
    return null;
  }

  String get selectedModel => activeConversation?.model ?? 'resnet';

  void attachSettings(SettingsProvider settings) {
    _settings = settings;
  }

  Future<void> loadHistory() async {
    loadingHistory = true;
    notifyListeners();
    try {
      conversations
        ..clear()
        ..addAll(await _db.loadConversations());
      sortConversationsByRecent(conversations);
      await _selectOrCreateFreshConversation();
    } catch (e) {
      lastError = e.toString();
    } finally {
      loadingHistory = false;
      notifyListeners();
    }
  }

  /// Mở app/tab AI: ưu tiên cuộc trò chuyện trống, không thì tạo mới.
  Future<void> _selectOrCreateFreshConversation() async {
    for (final conv in conversations) {
      if (conv.title == 'Cuộc trò chuyện mới') {
        final count = await _db.countMessages(conv.id);
        if (count == 0) {
          activeConversationId = conv.id;
          messages.clear();
          return;
        }
      }
    }
    await createNewConversation(select: true);
  }

  Future<void> createNewConversation({bool select = true}) async {
    lastError = null;
    final conv = await _db.createConversation();
    conversations.add(conv);
    sortConversationsByRecent(conversations);
    if (select) {
      activeConversationId = conv.id;
      messages.clear();
    }
    notifyListeners();
  }

  Future<void> selectConversation(int id) async {
    if (activeConversationId == id) return;
    activeConversationId = id;
    lastError = null;
    loadingHistory = true;
    notifyListeners();
    try {
      await _loadMessagesForActive();
    } catch (e) {
      lastError = e.toString();
    } finally {
      loadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> deleteConversation(int id) async {
    await _db.deleteConversation(id);
    conversations.removeWhere((c) => c.id == id);
    sortConversationsByRecent(conversations);
    if (activeConversationId == id) {
      if (conversations.isEmpty) {
        await createNewConversation(select: true);
      } else {
        await selectConversation(conversations.first.id);
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> renameConversation(int id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await _db.updateConversation(id: id, title: trimmed);
    final index = conversations.indexWhere((c) => c.id == id);
    if (index >= 0) {
      conversations[index] = conversations[index].copyWith(title: trimmed);
      notifyListeners();
    }
  }

  Future<void> setSelectedModel(String model) async {
    final convId = activeConversationId;
    if (convId == null) return;
    await _db.updateConversation(id: convId, model: model);
    final index = conversations.indexWhere((c) => c.id == convId);
    if (index >= 0) {
      conversations[index] = conversations[index].copyWith(model: model);
    }
    notifyListeners();
  }

  Future<void> _loadMessagesForActive() async {
    final convId = activeConversationId;
    if (convId == null) {
      messages.clear();
      return;
    }
    final list = await _db.loadMessages(convId);
    messages
      ..clear()
      ..addAll(list);
  }

  Future<int> _ensureConversationId() async {
    if (activeConversationId != null) return activeConversationId!;
    await createNewConversation(select: true);
    return activeConversationId!;
  }

  Future<void> _maybeRenameConversation(int conversationId, String text) async {
    final conv = conversations.firstWhere((c) => c.id == conversationId);
    if (conv.title != 'Cuộc trò chuyện mới') return;
    final count = await _db.countMessages(conversationId);
    if (count > 1) return;

    final title = _titleFromMessage(text);
    await _db.updateConversation(id: conversationId, title: title);
    final index = conversations.indexWhere((c) => c.id == conversationId);
    if (index >= 0) {
      conversations[index] = conversations[index].copyWith(title: title);
    }
  }

  String _titleFromMessage(String text) {
    final cleaned = text.replaceAll('\n', ' ').trim();
    if (cleaned.isEmpty) return 'Cuộc trò chuyện mới';
    if (cleaned.length <= 42) return cleaned;
    return '${cleaned.substring(0, 42).trim()}…';
  }

  Future<String?> pickImageAndPredict({String? model}) async {
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

    final resolvedModel = model ?? selectedModel;
    sending = true;
    lastError = null;
    notifyListeners();

    try {
      final convId = await _ensureConversationId();
      final userText = '[Ảnh đính kèm - $resolvedModel]';
      final userRow = await _db.insertMessage(
        conversationId: convId,
        text: userText,
        senderType: SenderType.user,
        localImagePath: file.path,
      );
      messages.add(userRow);
      await _maybeRenameConversation(convId, userText);
      _touchConversation(convId);
      notifyListeners();

      final map = await _ai.predictImageFile(
        predictEndpoint: endpoint,
        imageFile: File(file.path),
        model: resolvedModel,
      );
      final reply = formatPredictReply(map, model: resolvedModel);
      final aiRow = await _db.insertMessage(
        conversationId: convId,
        text: reply,
        senderType: SenderType.ai,
      );
      messages.add(aiRow);
      _touchConversation(convId);
      return reply;
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<String?> analyzeCurrentCameraImage({
    String? model,
    String? preferredImageUrl,
  }) async {
    final resolvedModel = model ?? selectedModel;
    final endpoint = _settings?.predictEndpoint ?? '';
    final serverBase = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (endpoint.isEmpty) {
      lastError = 'Chưa cấu hình URL AI Server';
      notifyListeners();
      return null;
    }
    if (serverBase.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key trong Cài đặt';
      notifyListeners();
      return null;
    }

    sending = true;
    lastError = null;
    notifyListeners();
    try {
      final convId = await _ensureConversationId();
      final imageUrl = await _resolveLatestCameraUrl(
        serverBase: serverBase,
        apiKey: apiKey,
        preferredImageUrl: preferredImageUrl,
      );
      final imageBytes = await _downloadImageBytes(imageUrl);
      final flippedBytes = await _flipImageVertically(imageBytes);
      final previewImagePath = await _savePreviewImageBytes(flippedBytes);
      const filename = 'camera_latest_flipped.png';
      final userText = '[Kiểm tra sức khỏe cây - $resolvedModel]';
      final userRow = await _db.insertMessage(
        conversationId: convId,
        text: userText,
        senderType: SenderType.user,
        localImagePath: previewImagePath,
      );
      messages.add(userRow);
      await _maybeRenameConversation(convId, userText);
      _touchConversation(convId);
      notifyListeners();

      final map = await _ai.predictImageBytes(
        predictEndpoint: endpoint,
        bytes: flippedBytes,
        filename: filename,
        model: resolvedModel,
      );
      final reply = formatPredictReply(map, model: resolvedModel);
      final aiRow = await _db.insertMessage(
        conversationId: convId,
        text: reply,
        senderType: SenderType.ai,
      );
      messages.add(aiRow);
      _touchConversation(convId);
      return reply;
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  /// Gọi POST /api/camera/health-check — server chụp ảnh + AI (giống nút ESP32).
  Future<String?> runServerHealthCheck({GardenProvider? garden}) async {
    final resolvedModel = selectedModel;
    final serverBase = _settings?.serverUrl.trim() ?? '';
    final apiKey = _settings?.apiKey.trim() ?? '';
    if (serverBase.isEmpty || apiKey.isEmpty) {
      lastError = 'Thiếu URL server IoT hoặc API key trong Cài đặt';
      notifyListeners();
      return null;
    }

    sending = true;
    lastError = null;
    notifyListeners();
    try {
      final convId = await _ensureConversationId();
      final userText = '[Kiểm tra sức khỏe cây - $resolvedModel]';

      final map = await _esp32.requestHealthCheck(
        serverBase: serverBase,
        apiKey: apiKey,
        model: resolvedModel,
      );
      final reply = map['reply']?.toString().trim() ?? '';
      if (reply.isEmpty) {
        lastError = 'Server không trả kết quả phân tích.';
        return null;
      }

      String? previewImagePath;
      final rawImageUrl = map['image_url']?.toString().trim();
      if (rawImageUrl != null && rawImageUrl.isNotEmpty) {
        try {
          final imageUrl = _normalizeImageUrl(
            serverBase: serverBase,
            rawUrl: _cacheBustUrl(rawImageUrl),
          );
          final imageBytes = await _downloadImageBytes(imageUrl);
          final flippedBytes = await _flipImageVertically(imageBytes);
          previewImagePath = await _savePreviewImageBytes(flippedBytes);
          if (garden != null) {
            garden.latestImageUrl = imageUrl;
            garden.notifyListeners();
          }
        } catch (e) {
          debugPrint('Health check image preview failed: $e');
        }
      }

      final userRow = await _db.insertMessage(
        conversationId: convId,
        text: userText,
        senderType: SenderType.user,
        localImagePath: previewImagePath,
      );
      messages.add(userRow);
      await _maybeRenameConversation(convId, userText);

      final aiRow = await _db.insertMessage(
        conversationId: convId,
        text: reply,
        senderType: SenderType.ai,
      );
      messages.add(aiRow);
      _touchConversation(convId);
      return reply;
    } on Esp32HttpException catch (e) {
      lastError = e.toString();
      rethrow;
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  Future<String?> runSmartSuggestion({
    required String intent,
    required GardenProvider garden,
  }) async {
    final normalized = intent.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    sending = true;
    lastError = null;
    notifyListeners();
    try {
      await garden.refreshWaterTodayCount();
      await garden.refreshWateringPlan();
      await garden.refreshActiveGrowingCycle();

      final convId = await _ensureConversationId();
      final userRow = await _db.insertMessage(
        conversationId: convId,
        text: intent,
        senderType: SenderType.user,
      );
      messages.add(userRow);
      await _maybeRenameConversation(convId, intent);
      _touchConversation(convId);
      notifyListeners();

      final reply = switch (normalized) {
        'dự báo thu hoạch' => _buildHarvestForecast(garden),
        'gợi ý lịch tưới' => _buildWateringAdvice(garden),
        _ => await _mockOrForwardToAi(intent),
      };

      final aiRow = await _db.insertMessage(
        conversationId: convId,
        text: reply,
        senderType: SenderType.ai,
      );
      messages.add(aiRow);
      _touchConversation(convId);
      return reply;
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  void _touchConversation(int conversationId, {DateTime? updatedAt}) {
    final now = updatedAt ?? DateTime.now();
    final index = conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;
    conversations[index] = conversations[index].copyWith(updatedAt: now);
    sortConversationsByRecent(conversations);
  }

  String _buildHarvestForecast(GardenProvider garden) {
    final t = garden.airTemperatureC;
    final soil = garden.currentMoisture;
    final humid = garden.airHumidityPct;
    final rain = garden.rainPercent;
    final pumpCount = garden.waterTodayCount;

    const harvestTargetDays = 45;
    final cycle = garden.activeGrowingCycle;
    final hasCycle = cycle != null && cycle.isActive;
    final harvestProgress = hasCycle
        ? '${cycle.daysElapsed}/$harvestTargetDays'
        : '—/$harvestTargetDays';
    final daysUntilHarvest = hasCycle
        ? (harvestTargetDays - cycle.daysElapsed).clamp(0, harvestTargetDays)
        : null;
    final forecastHarvestDate = hasCycle
        ? DateTime(
            cycle.startedAt.year,
            cycle.startedAt.month,
            cycle.startedAt.day,
          ).add(Duration(days: harvestTargetDays - 1))
        : null;
    final forecastLine = forecastHarvestDate == null
        ? 'Dự báo ngày thu hoạch: — (bắt đầu chu kỳ ở Điều khiển)'
        : daysUntilHarvest == 0
            ? 'Dự báo ngày thu hoạch: ${_formatDateVN(forecastHarvestDate)} (hôm nay)'
            : 'Dự báo ngày thu hoạch: ${_formatDateVN(forecastHarvestDate)} (còn $daysUntilHarvest ngày)';

    return [
      'Tiến trình: $harvestProgress',
      forecastLine,
      '',
      'Thông số phân tích:',
      '- Nhiệt độ: ${_fmt(t, 1)}°C (mục tiêu 22-32°C)',
      '- Ẩm đất: ${soil?.toString() ?? '—'}% (mục tiêu 45-85%)',
      '- Ẩm không khí: ${_fmt(humid, 0)}% (mục tiêu 45-85%)',
      '- Mưa: ${rain?.toString() ?? '—'}%',
      '- Số lần chạy bơm hôm nay: $pumpCount',
    ].join('\n');
  }

  String _buildWateringAdvice(GardenProvider garden) {
    final t = garden.airTemperatureC;
    final soil = garden.currentMoisture;
    final humid = garden.airHumidityPct;
    final rain = garden.rainPercent;
    final pumpCount = garden.waterTodayCount;
    final standardPerDay = garden.wateringSessionsPerDay;

    var remainingToday =
        (standardPerDay - pumpCount).clamp(0, standardPerDay);
    if (soil != null && soil >= 70) remainingToday = 0;
    if (rain != null && rain >= 75) remainingToday = 0;

    final scheduleLine = garden.wateringBoostActive
        ? 'Lịch tự động: 6:00, 12:00, 17:00 (tăng do ẩm đất TB thấp).'
        : 'Lịch tự động: 6:00 và 17:00.';

    return [
      'Gợi ý lịch tưới:',
      '- Số lần tưới đề xuất hôm nay: $standardPerDay',
      '- Còn lại hôm nay: $remainingToday',
      scheduleLine,
      if (garden.wateringBoostActive)
        'Hệ thống đang tăng tưới lên 3 lần/ngày vì ẩm đất trung bình dưới ngưỡng an toàn.',
      'Lưu ý: Nên tưới vào sáng, trưa (nếu có), chiều; hạn chế tưới lúc nắng gắt.',
      '',
      'Thông số phân tích:',
      '- Ẩm đất hiện tại: ${soil?.toString() ?? '—'}%',
      '- Nhiệt độ: ${_fmt(t, 1)}°C',
      '- Ẩm không khí: ${_fmt(humid, 0)}%',
      '- Mưa: ${rain?.toString() ?? '—'}%',
      '- Số lần chạy bơm hôm nay: $pumpCount',
    ].join('\n');
  }

  String _fmt(double? value, int decimals) {
    if (value == null) return '—';
    return value.toStringAsFixed(decimals);
  }

  String _formatDateVN(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  String _cacheBustUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final sep = u.contains('?') ? '&' : '?';
    return '$u${sep}cb=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _resolveLatestCameraUrl({
    required String serverBase,
    required String apiKey,
    String? preferredImageUrl,
  }) async {
    final preferred = preferredImageUrl?.trim() ?? '';
    if (preferred.isNotEmpty) {
      return _normalizeImageUrl(
        serverBase: serverBase,
        rawUrl: _cacheBustUrl(preferred),
      );
    }
    final imageMap = await _esp32.fetchLatestImage(
      serverBase: serverBase,
      apiKey: apiKey,
    );
    final rawImage = imageMap['image'];
    String? imageUrl;
    if (rawImage is Map) {
      imageUrl = rawImage['url']?.toString();
    } else if (rawImage is String) {
      imageUrl = rawImage;
    }
    imageUrl ??= imageMap['url']?.toString();
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      throw StateError('Chưa có ảnh camera mới nhất để phân tích');
    }
    return _normalizeImageUrl(
      serverBase: serverBase,
      rawUrl: _cacheBustUrl(imageUrl),
    );
  }

  String _normalizeImageUrl({
    required String serverBase,
    required String rawUrl,
  }) {
    final cleaned = rawUrl.trim();
    final uri = Uri.tryParse(cleaned);
    if (uri != null && uri.hasScheme) return cleaned;
    final baseWithScheme = serverBase.startsWith('http://') || serverBase.startsWith('https://')
        ? serverBase
        : 'http://$serverBase';
    return Uri.parse(baseWithScheme).resolve(cleaned).toString();
  }

  Future<Uint8List> _downloadImageBytes(String imageUrl) async {
    final uri = Uri.parse(imageUrl);
    final request = await HttpClient().getUrl(uri);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Không tải được ảnh camera: HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final mime = response.headers.contentType?.mimeType ?? '';
    if (mime.isNotEmpty && !mime.startsWith('image/')) {
      throw StateError('URL camera không trả ảnh (mime=$mime): $imageUrl');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      throw const FormatException('Ảnh camera trống, không thể phân tích');
    }
    return bytes;
  }

  Future<String> _savePreviewImageBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'ai_check_${DateTime.now().millisecondsSinceEpoch}.png';
    final filePath = p.join(dir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  Future<Uint8List> _flipImageVertically(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(0, image.height.toDouble());
    canvas.scale(1, -1);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    final flipped = await recorder.endRecording().toImage(image.width, image.height);
    final byteData = await flipped.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw const FormatException('Không thể xử lý ảnh camera để lật dọc');
    }
    return byteData.buffer.asUint8List();
  }

  static String formatPredictReply(
    Map<String, dynamic> json, {
    String? model,
  }) {
    final payload = (json['result'] is Map<String, dynamic>)
        ? json['result'] as Map<String, dynamic>
        : json;
    final label = payload['label_vietnamese'] ??
        payload['label'] ??
        payload['prediction'] ??
        payload['disease'] ??
        payload['class'] ??
        payload['result'];
    final conf =
        payload['confidence'] ?? payload['score'] ?? payload['prob'] ?? payload['probability'];
    final modelTag = model == null || model.trim().isEmpty ? '' : ' [$model]';
    if (label != null && conf is num) {
      final pct = (conf <= 1 ? conf * 100 : conf).clamp(0, 100).round();
      return 'Phát hiện$modelTag: $label — $pct%';
    }
    if (label != null) return 'Phát hiện$modelTag: ${label.toString()}';
    return payload['message']?.toString() ?? json['message']?.toString() ?? payload.toString();
  }

  Future<String> _mockOrForwardToAi(String userText) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return 'Smart Garden: "$userText" — chỉ hỗ trợ gợi ý nhanh và phân tích ảnh.';
  }

  @override
  void dispose() {
    _ai.close();
    _esp32.close();
    super.dispose();
  }
}
