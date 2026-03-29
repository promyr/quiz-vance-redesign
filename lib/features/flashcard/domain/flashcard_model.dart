enum FsrsGrade { again, hard, good, easy }

/// Parse seguro de DateTime: retorna [fallback] se [value] for nulo ou mal formatado.
DateTime _parseDate(dynamic value, DateTime fallback) {
  if (value == null) return fallback;
  try {
    return DateTime.parse(value as String);
  } on FormatException {
    return fallback;
  }
}

class Flashcard {
  const Flashcard({
    required this.id,
    this.remoteId,
    required this.front,
    required this.back,
    this.topic,
    this.intervalDays = 1,
    this.easiness = 2.5,
    required this.dueDate,
    this.repetitions = 0,
    this.lastReviewed,
    this.synced = false,
    required this.createdAt,
  });

  factory Flashcard.fromJson(Map<String, dynamic> json) => Flashcard(
        // Suporte a id numérico ou string (backends distintos)
        id: json['id'] != null ? (json['id'] as num).toInt() : 0,
        remoteId: json['remote_id'] as String?,
        front: (json['front'] as String?) ?? '',
        back: (json['back'] as String?) ?? '',
        topic: json['topic'] as String?,
        intervalDays: (json['interval_days'] as num?)?.toInt() ?? 1,
        easiness: (json['easiness'] as num?)?.toDouble() ?? 2.5,
        dueDate: _parseDate(json['due_date'], DateTime.now()),
        repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
        lastReviewed: json['last_reviewed'] != null
            ? _parseDate(json['last_reviewed'], DateTime.now())
            : null,
        synced: (json['synced'] as bool?) ?? false,
        createdAt: _parseDate(json['created_at'], DateTime.now()),
      );

  factory Flashcard.fromDb(Map<String, dynamic> row) => Flashcard(
        id: (row['id'] as int?) ?? 0,
        remoteId: row['remote_id'] as String?,
        front: (row['front'] as String?) ?? '',
        back: (row['back'] as String?) ?? '',
        topic: row['topic'] as String?,
        intervalDays: (row['interval_days'] as int?) ?? 1,
        easiness: (row['easiness'] as num?)?.toDouble() ?? 2.5,
        dueDate: _parseDate(row['due_date'], DateTime.now()),
        repetitions: (row['repetitions'] as int?) ?? 0,
        lastReviewed: row['last_reviewed'] != null
            ? _parseDate(row['last_reviewed'], DateTime.now())
            : null,
        synced: (row['synced'] as int?) == 1,
        createdAt: _parseDate(row['created_at'], DateTime.now()),
      );

  final int id;
  final String? remoteId;
  final String front;
  final String back;
  final String? topic;
  final int intervalDays;
  final double easiness;
  final DateTime dueDate;
  final int repetitions;
  final DateTime? lastReviewed;
  final bool synced;
  final DateTime createdAt;

  Flashcard copyWith({
    int? id,
    String? remoteId,
    String? front,
    String? back,
    String? topic,
    int? intervalDays,
    double? easiness,
    DateTime? dueDate,
    int? repetitions,
    DateTime? lastReviewed,
    bool? synced,
    DateTime? createdAt,
  }) {
    return Flashcard(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      front: front ?? this.front,
      back: back ?? this.back,
      topic: topic ?? this.topic,
      intervalDays: intervalDays ?? this.intervalDays,
      easiness: easiness ?? this.easiness,
      dueDate: dueDate ?? this.dueDate,
      repetitions: repetitions ?? this.repetitions,
      lastReviewed: lastReviewed ?? this.lastReviewed,
      synced: synced ?? this.synced,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
