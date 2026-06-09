class ChatConversation {
  ChatConversation({
    required this.id,
    required this.title,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatConversation copyWith({
    String? title,
    String? model,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id,
      title: title ?? this.title,
      model: model ?? this.model,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'model': model,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static ChatConversation fromMap(Map<String, Object?> map) {
    return ChatConversation(
      id: map['id'] as int,
      title: map['title'] as String,
      model: map['model'] as String? ?? 'resnet',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }
}
