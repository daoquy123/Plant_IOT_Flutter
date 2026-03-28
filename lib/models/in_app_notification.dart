class InAppNotification {
  InAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  static InAppNotification fromJson(Map<String, dynamic> j) {
    return InAppNotification(
      id: j['id'] as String,
      title: j['title'] as String,
      body: j['body'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
    );
  }
}
