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
    this.isMastered = false,
  });

  final String id;
  final String topic;
  final Question question;
  final DateTime failedAt;
  final int timesFailed;
  final bool isMastered;

  ErrorQuestion copyWith({
    String? id,
    String? topic,
    Question? question,
    DateTime? failedAt,
    int? timesFailed,
    bool? isMastered,
  }) {
    return ErrorQuestion(
      id: id ?? this.id,
      topic: topic ?? this.topic,
      question: question ?? this.question,
      failedAt: failedAt ?? this.failedAt,
      timesFailed: timesFailed ?? this.timesFailed,
      isMastered: isMastered ?? this.isMastered,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topic': topic,
      'question': question.toJson(),
      'failed_at': failedAt.toIso8601String(),
      'times_failed': timesFailed,
      'is_mastered': isMastered,
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
      isMastered: json['is_mastered'] as bool? ?? false,
    );
  }
}
