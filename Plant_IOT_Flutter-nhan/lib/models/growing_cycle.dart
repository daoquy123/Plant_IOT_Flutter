class GrowingCycle {
  GrowingCycle({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.note,
    this.createdAt,
  });

  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? note;
  final DateTime? createdAt;

  bool get isActive => endedAt == null;

  /// Số ngày tính từ ngày bắt đầu (ngày 1 = ngày trồng).
  int get daysElapsed {
    final start = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final endRaw = endedAt ?? DateTime.now();
    final end = DateTime(endRaw.year, endRaw.month, endRaw.day);
    return end.difference(start).inDays + 1;
  }

  static GrowingCycle? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final id = json['id'];
    final started = json['started_at']?.toString();
    if (id == null || started == null || started.isEmpty) return null;
    return GrowingCycle(
      id: id is int ? id : int.tryParse(id.toString()) ?? 0,
      startedAt: DateTime.parse(started).toLocal(),
      endedAt: _parseOptional(json['ended_at']),
      note: json['note']?.toString(),
      createdAt: _parseOptional(json['created_at']),
    );
  }

  static DateTime? _parseOptional(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.parse(s).toLocal();
  }

  String get startedLabel {
    final d = startedAt;
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day/$month/${d.year}';
  }
}
