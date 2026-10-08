import 'dart:convert';
import '../../quiz/domain/question_model.dart';

/// Representa uma questão que o usuário errou durante um quiz,
/// armazenada no Caderno de Erros para revisão inteligente.
class ErrorQuestion {
  const ErrorQuestion({
    required this.id,
    required this.topic,
    required this.question,
    required this.failedAt,
    this.timesFailed = 1,
    this.consecutiveCorrect = 0,
    this.isMastered = false,
    this.failedSessionIds = const [],
  });

  final String id;
  final String topic;
  final Question question;
  final DateTime failedAt;
  final int timesFailed;
  final int consecutiveCorrect;
  final bool isMastered;
  final List<String> failedSessionIds;

  ErrorQuestion copyWith({
    String? id,
    String? topic,
    Question? question,
    DateTime? failedAt,
    int? timesFailed,
    int? consecutiveCorrect,
    bool? isMastered,
    List<String>? failedSessionIds,
  }) {
    return ErrorQuestion(
      id: id ?? this.id,
      topic: topic ?? this.topic,
      question: question ?? this.question,
      failedAt: failedAt ?? this.failedAt,
      timesFailed: timesFailed ?? this.timesFailed,
      consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
      isMastered: isMastered ?? this.isMastered,
      failedSessionIds: failedSessionIds ?? this.failedSessionIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topic': topic,
      'question': question.toJson(),
      'failed_at': failedAt.toIso8601String(),
      'times_failed': timesFailed,
      'consecutive_correct': consecutiveCorrect,
      'is_mastered': isMastered,
      'failed_session_ids': failedSessionIds,
    };
  }

  factory ErrorQuestion.fromJson(Map<String, dynamic> json) {
    final rawQuestion = json['question'];
    final questionMap = rawQuestion is Map<String, dynamic>
        ? rawQuestion
        : jsonDecode(rawQuestion.toString()) as Map<String, dynamic>;

    return ErrorQuestion(
      id: json['id'] as String? ?? questionMap['id']?.toString() ?? '',
      topic: json['topic'] as String? ?? 'Geral',
      question: Question.fromJson(questionMap),
      failedAt: json['failed_at'] != null
          ? DateTime.tryParse(json['failed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      timesFailed: json['times_failed'] as int? ?? 1,
      consecutiveCorrect: json['consecutive_correct'] as int? ?? 0,
      isMastered: json['is_mastered'] as bool? ?? false,
      failedSessionIds:
          (json['failed_session_ids'] as List?)?.whereType<String>().toList() ??
              const [],
    );
  }
}
