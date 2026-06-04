/// Chuyển lỗi mạng/HTTP thành thông báo ngắn gọn cho người dùng.
String friendlyNetworkError(Object error, {String? serverUrl}) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (error is StateError) {
    return raw.replaceFirst('Bad state: ', '').replaceFirst('StateError: ', '');
  }
  if (error is FormatException) {
    return raw.replaceFirst('FormatException: ', '');
  }

  if (lower.contains('unauthorized') ||
      lower.contains('401') ||
      lower.contains('missing or invalid x-api-key')) {
    return 'API key không hợp lệ. Kiểm tra lại trong Cài đặt.';
  }

  if (lower.contains('timeout') ||
      lower.contains('semaphore timeout') ||
      lower.contains('connection timed out') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable') ||
      lower.contains('socketexception')) {
    final host = serverUrl?.trim();
    if (host != null && host.isNotEmpty) {
      return 'Không kết nối được server $host. Kiểm tra mạng hoặc đổi Server URL trong Cài đặt.';
    }
    return 'Không kết nối được server IoT. Kiểm tra mạng hoặc cấu hình trong Cài đặt.';
  }

  if (lower.contains('esp32httpexception')) {
    return 'Server trả lỗi. Kiểm tra API key và trạng thái backend.';
  }

  return 'Không tải được dữ liệu phân tích. Thử lại sau.';
}
