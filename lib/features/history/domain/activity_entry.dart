/// Representa uma sessão de quiz ou simulado no histórico do usuário.
class ActivityEntry {
  const ActivityEntry({
    required this.eventId,
    required this.total,
    required this.correct,
    required this.xpEarned,
    required this.accuracy,
    required this.createdAt,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      eventId: json['event_id'] as String? ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      correct: (json['correct'] as num?)?.toInt() ?? 0,
      xpEarned: (json['xp_earned'] as num?)?.toInt() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  final String eventId;
  final int total;
  final int correct;
  final int xpEarned;
  final double accuracy;
  final DateTime createdAt;

  int get wrong => total - correct;
}
