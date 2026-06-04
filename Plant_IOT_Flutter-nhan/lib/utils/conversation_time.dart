import '../models/chat_conversation.dart';

enum ConversationTimeGroup {
  today,
  yesterday,
  last7Days,
  last30Days,
  older,
}

extension ConversationTimeGroupLabel on ConversationTimeGroup {
  String get label => switch (this) {
        ConversationTimeGroup.today => 'Hôm nay',
        ConversationTimeGroup.yesterday => 'Hôm qua',
        ConversationTimeGroup.last7Days => '7 ngày qua',
        ConversationTimeGroup.last30Days => '30 ngày qua',
        ConversationTimeGroup.older => 'Trước đó',
      };
}

ConversationTimeGroup conversationTimeGroup(DateTime updatedAt) {
  final now = DateTime.now();
  final local = updatedAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return ConversationTimeGroup.today;
  if (diff == 1) return ConversationTimeGroup.yesterday;
  if (diff <= 7) return ConversationTimeGroup.last7Days;
  if (diff <= 30) return ConversationTimeGroup.last30Days;
  return ConversationTimeGroup.older;
}

void sortConversationsByRecent(List<ChatConversation> conversations) {
  conversations.sort((a, b) {
    final byTime = b.updatedAt.compareTo(a.updatedAt);
    if (byTime != 0) return byTime;
    return b.id.compareTo(a.id);
  });
}

List<({ConversationTimeGroup group, List<ChatConversation> items})>
    groupConversationsByTime(List<ChatConversation> conversations) {
  final sorted = List<ChatConversation>.from(conversations);
  sortConversationsByRecent(sorted);

  final buckets = <ConversationTimeGroup, List<ChatConversation>>{};
  for (final conv in sorted) {
    final group = conversationTimeGroup(conv.updatedAt);
    buckets.putIfAbsent(group, () => []).add(conv);
  }

  const order = ConversationTimeGroup.values;
  return order
      .where((g) => buckets[g]?.isNotEmpty == true)
      .map((g) => (group: g, items: buckets[g]!))
      .toList();
}

String formatConversationTime(DateTime updatedAt) {
  final local = updatedAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;

  if (diff == 0) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  if (diff == 1) return 'Hôm qua';
  if (diff < 7) return '$diff ngày trước';
  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo/${local.year}';
}
