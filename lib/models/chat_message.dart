enum SenderType { user, ai }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.senderType,
    required this.createdAt,
    this.localImagePath,
  });

  final int id;
  final String text;
  final SenderType senderType;
  final DateTime createdAt;
  final String? localImagePath;

  Map<String, Object?> toMap() => {
        'id': id,
        'text': text,
        'sender_type': senderType == SenderType.user ? 'user' : 'ai',
        'created_at': createdAt.millisecondsSinceEpoch,
        'local_image_path': localImagePath,
      };

  static ChatMessage fromMap(Map<String, Object?> map) {
    return ChatMessage(
      id: map['id'] as int,
      text: map['text'] as String,
      senderType: (map['sender_type'] as String) == 'user'
          ? SenderType.user
          : SenderType.ai,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      localImagePath: map['local_image_path'] as String?,
    );
  }
}
