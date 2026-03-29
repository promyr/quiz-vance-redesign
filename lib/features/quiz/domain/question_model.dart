class QuizOption {
  const QuizOption({
    required this.id,
    required this.text,
    this.isCorrect = false,
  });

  factory QuizOption.fromJson(Map<String, dynamic> json) => QuizOption(
        id: json['id'] as String,
        text: json['text'] as String,
        isCorrect: (json['is_correct'] as bool?) ?? false,
      );

  final String id;
  final String text;
  final bool isCorrect;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'is_correct': isCorrect,
      };
}

class Question {
  const Question({
    required this.id,
    required this.text,
    required this.options,
    required this.correctOptionId,
    this.explanation,
    this.topic,
    this.difficulty = 'medium',
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'] as List<dynamic>? ?? [];
    final correctId = json['correct_option_id'] as String? ??
        json['correct_answer'] as String? ?? '';
    final options = rawOptions
        .map((e) => QuizOption.fromJson(e as Map<String, dynamic>))
        .toList();
    return Question(
      id: json['id']?.toString() ?? '',
      text: json['text'] as String? ?? json['question'] as String? ?? '',
      options: options,
      correctOptionId: correctId,
      explanation: json['explanation'] as String?,
      topic: json['topic'] as String?,
      difficulty: json['difficulty'] as String? ?? 'medium',
    );
  }

  final String id;
  final String text;
  final List<QuizOption> options;
  final String correctOptionId;
  final String? explanation;
  final String? topic;
  final String difficulty;
}

class QuestionAnswer {
  const QuestionAnswer({
    required this.question,
    required this.selectedOptionId,
    required this.isCorrect,
  });

  final Question question;
  final String? selectedOptionId;
  final bool isCorrect;
}

class QuizResult {
  const QuizResult({
    required this.sessionId,
    required this.total,
    required this.correct,
    required this.xpEarned,
    required this.timeTaken,
    required this.answers,
    this.topic,
  });

  final String sessionId;
  final int total;
  final int correct;
  final int xpEarned;
  final Duration timeTaken;
  final List<QuestionAnswer> answers;
  final String? topic;

  double get accuracy => total > 0 ? correct / total : 0.0;
}
