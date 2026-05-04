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
import '../models/chat_message.dart';
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

  final List<ChatMessage> messages = [];
  bool loadingHistory = true;
  bool sending = false;
  String? lastError;

  static const suggestions = <String>[
    'Kiểm tra sức khỏe cây',
    'Dự báo thu hoạch',
    'Gợi ý lịch tưới',
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

    sending = true;
    lastError = null;
    notifyListeners();

    try {
      final userRow = await _db.insertMessage(
        text: model == null || model.trim().isEmpty
            ? '[Ảnh đính kèm]'
            : '[Ảnh đính kèm - ${model.trim()}]',
        senderType: SenderType.user,
        localImagePath: file.path,
      );
      messages.add(userRow);
      notifyListeners();

      final map = await _ai.predictImageFile(
        predictEndpoint: endpoint,
        imageFile: File(file.path),
        model: model,
      );
      final reply = formatPredictReply(map, model: model);
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

  Future<String?> analyzeCurrentCameraImage({
    required String model,
    String? preferredImageUrl,
  }) async {
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
      final imageUrl = await _resolveLatestCameraUrl(
        serverBase: serverBase,
        apiKey: apiKey,
        preferredImageUrl: preferredImageUrl,
      );
      final imageBytes = await _downloadImageBytes(imageUrl);
      final flippedBytes = await _flipImageVertically(imageBytes);
      final previewImagePath = await _savePreviewImageBytes(flippedBytes);
      const filename = 'camera_latest_flipped.png';
      final userRow = await _db.insertMessage(
        text: '[Kiểm tra sức khỏe cây - $model]',
        senderType: SenderType.user,
        localImagePath: previewImagePath,
      );
      messages.add(userRow);
      notifyListeners();

      final map = await _ai.predictImageBytes(
        predictEndpoint: endpoint,
        bytes: flippedBytes,
        filename: filename,
        model: model,
      );
      final reply = formatPredictReply(map, model: model);
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
      final userRow = await _db.insertMessage(
        text: intent,
        senderType: SenderType.user,
      );
      messages.add(userRow);
      notifyListeners();

      final reply = switch (normalized) {
        'dự báo thu hoạch' => _buildHarvestForecast(garden),
        'gợi ý lịch tưới' => _buildWateringAdvice(garden),
        _ => await _mockOrForwardToAi(intent),
      };

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

  String _buildHarvestForecast(GardenProvider garden) {
    final t = garden.airTemperatureC;
    final soil = garden.currentMoisture;
    final humid = garden.airHumidityPct;
    final rain = garden.rainPercent;
    final pumpCount = garden.waterTodayCount;

    final tempScore = _scoreRange(t, min: 22, max: 32, best: 27);
    final soilScore = _scoreRange(soil?.toDouble(), min: 45, max: 85, best: 65);
    final humidScore = _scoreRange(humid, min: 45, max: 85, best: 65);
    final rainPenalty = (rain != null && rain > 85) ? 6 : 0;
    final pumpPenalty = pumpCount >= 8 ? 8 : (pumpCount >= 6 ? 4 : 0);

    final baseScore =
        ((tempScore * 0.35) + (soilScore * 0.4) + (humidScore * 0.25)).round();
    final stabilityScore = (baseScore - rainPenalty - pumpPenalty).clamp(0, 100);

    final days = switch (stabilityScore) {
      >= 80 => '7-10 ngày',
      >= 65 => '10-14 ngày',
      >= 50 => '14-20 ngày',
      _ => 'trên 20 ngày',
    };
    final risk = switch (stabilityScore) {
      >= 80 => 'Thấp',
      >= 65 => 'Trung bình',
      _ => 'Cao',
    };

    return [
      'Dự báo thu hoạch:',
      '- Điểm sinh trưởng hiện tại: $stabilityScore/100',
      '- Thời gian thu hoạch ước tính: $days',
      '- Mức rủi ro chậm phát triển: $risk',
      '',
      'Thông số phân tích:',
      '- Nhiệt độ: ${_fmt(t, 1)}°C (mục tiêu 22-32°C)',
      '- Ẩm đất: ${soil?.toString() ?? '—'}% (mục tiêu 45-85%)',
      '- Ẩm không khí: ${_fmt(humid, 0)}% (mục tiêu 45-85%)',
      '- Mưa: ${rain?.toString() ?? '—'}%',
      '- Số lần chạy bơm hôm nay: $pumpCount',
      '',
      'Khuyến nghị nhanh:',
      '- Duy trì ẩm đất quanh 60-70%, tránh dao động lớn.',
      '- Nếu mưa cao liên tục, giảm tưới tay để hạn chế úng rễ.',
    ].join('\n');
  }

  String _buildWateringAdvice(GardenProvider garden) {
    final t = garden.airTemperatureC;
    final soil = garden.currentMoisture;
    final humid = garden.airHumidityPct;
    final rain = garden.rainPercent;
    final pumpCount = garden.waterTodayCount;

    final soilNeed = soil == null
        ? 2
        : soil < 40
            ? 3
            : soil < 50
                ? 2
                : soil < 65
                    ? 1
                    : 0;
    final heatBoost = (t != null && t >= 33) ? 1 : 0;
    final dryAirBoost = (humid != null && humid < 45) ? 1 : 0;
    final rainReduce = (rain != null && rain >= 75) ? 2 : ((rain != null && rain >= 55) ? 1 : 0);

    final suggestedCycles = (soilNeed + heatBoost + dryAirBoost - rainReduce).clamp(0, 4);
    final nextSlot = switch (suggestedCycles) {
      0 => 'Tạm hoãn 8-12 giờ',
      1 => '1 lần vào sáng sớm',
      2 => '2 lần: sáng sớm + chiều mát',
      3 => '3 lần: sáng + trưa ngắn + chiều',
      _ => '3-4 lần, chia ngắn theo chu kỳ',
    };
    final durationSec = switch (suggestedCycles) {
      0 => 0,
      1 => 10,
      2 => 12,
      3 => 15,
      _ => 18,
    };

    return [
      'Gợi ý lịch tưới:',
      '- Chu kỳ đề xuất hôm nay: $suggestedCycles lần',
      '- Khung tưới: $nextSlot',
      '- Thời lượng mỗi lần (gợi ý): ${durationSec}s',
      '',
      'Thông số phân tích:',
      '- Ẩm đất hiện tại: ${soil?.toString() ?? '—'}%',
      '- Nhiệt độ: ${_fmt(t, 1)}°C',
      '- Ẩm không khí: ${_fmt(humid, 0)}%',
      '- Mưa: ${rain?.toString() ?? '—'}%',
      '- Số lần chạy bơm hôm nay: $pumpCount',
      '',
      'Khuyến nghị vận hành:',
      if (suggestedCycles == 0)
        '- Đất đang đủ ẩm hoặc mưa cao, tạm dừng tưới để tránh úng.'
      else
        '- Sau mỗi lần tưới, chờ 10-15 phút rồi đọc lại ẩm đất để hiệu chỉnh.',
      if (pumpCount >= 6)
        '- Máy bơm chạy nhiều, kiểm tra rò rỉ/thoát nước để tránh lãng phí.'
      else
        '- Theo dõi mốc ẩm đất 55-65% để giữ ổn định cho cây.',
    ].join('\n');
  }

  int _scoreRange(
    double? value, {
    required double min,
    required double max,
    required double best,
  }) {
    if (value == null) return 50;
    if (value < min) {
      return (100 - ((min - value) * 5)).clamp(0, 100).round();
    }
    if (value > max) {
      return (100 - ((value - max) * 5)).clamp(0, 100).round();
    }
    final distance = (value - best).abs();
    return (100 - distance * 3).clamp(0, 100).round();
  }

  String _fmt(double? value, int decimals) {
    if (value == null) return '—';
    return value.toStringAsFixed(decimals);
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

  /// Khi bạn có API chat thật, thay nội dung hàm này bằng HTTP tới server.
  Future<String> _mockOrForwardToAi(String userText) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return 'Smart Garden (demo): bạn đã gửi "$userText". '
        'Kết nối endpoint chat thật trong `ChatProvider._mockOrForwardToAi`.';
  }

  @override
  void dispose() {
    _ai.close();
    _esp32.close();
    super.dispose();
  }
}