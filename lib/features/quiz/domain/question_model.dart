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
    final options = rawOptions
        .map((e) => QuizOption.fromJson(e as Map<String, dynamic>))
        .toList();
    final rawCorrect = _stringValue(
      json['correct_option_id'] ?? json['correct_answer'],
    );
    return Question(
      id: json['id']?.toString() ?? '',
      text: json['text'] as String? ?? json['question'] as String? ?? '',
      options: options,
      correctOptionId: _resolveCorrectOptionId(
        rawCorrect: rawCorrect,
        options: options,
      ),
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

  QuizOption? get correctOption {
    for (final option in options) {
      if (option.id == correctOptionId) {
        return option;
      }
    }
    return null;
  }

  String? get correctOptionLetter {
    final index = options.indexWhere((option) => option.id == correctOptionId);
    if (index < 0) {
      return null;
    }
    return String.fromCharCode(65 + index);
  }
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

String _resolveCorrectOptionId({
  required String rawCorrect,
  required List<QuizOption> options,
}) {
  final directMatch = _findOptionIdByCandidate(rawCorrect, options);
  if (directMatch != null) {
    return directMatch;
  }

  final strippedCandidate = _stripAnswerPrefix(rawCorrect);
  final strippedMatch = _findOptionIdByCandidate(strippedCandidate, options);
  if (strippedMatch != null) {
    return strippedMatch;
  }

  final letter = _extractAnswerLetter(rawCorrect);
  if (letter != null) {
    final index = letter.codeUnitAt(0) - 97;
    if (index >= 0 && index < options.length) {
      return options[index].id;
    }
  }

  for (final option in options) {
    if (option.isCorrect) {
      return option.id;
    }
  }

  return rawCorrect;
}

String? _findOptionIdByCandidate(
    String rawCandidate, List<QuizOption> options) {
  final candidate = _normalizeAnswer(rawCandidate);
  if (candidate.isEmpty) {
    return null;
  }

  for (final option in options) {
    if (_normalizeAnswer(option.id) == candidate) {
      return option.id;
    }
  }

  for (final option in options) {
    if (_normalizeAnswer(option.text) == candidate) {
      return option.id;
    }
  }

  return null;
}

String? _extractAnswerLetter(String rawValue) {
  final normalized = _normalizeAnswer(_stripLeadingAnswerLabel(rawValue));
  if (normalized.isEmpty) {
    return null;
  }

  final exactLetter = RegExp(r'^([a-z])$').firstMatch(normalized);
  if (exactLetter != null) {
    return exactLetter.group(1);
  }

  final prefixedLetter =
      RegExp(r'^([a-z])[\)\].:\-\s]+').firstMatch(normalized);
  if (prefixedLetter != null) {
    return prefixedLetter.group(1);
  }

  return null;
}

String _stripAnswerPrefix(String rawValue) {
  final withoutLabel = _stripLeadingAnswerLabel(rawValue);
  return withoutLabel
      .replaceFirst(
        RegExp(r'^[a-z][\)\].:\-\s]+', caseSensitive: false),
        '',
      )
      .trim();
}

String _stripLeadingAnswerLabel(String rawValue) {
  return _normalizeAnswer(rawValue).replaceFirst(
    RegExp(r'^(alternativa|opção|opcao|letra)\s+', caseSensitive: false),
    '',
  );
}

String _normalizeAnswer(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _stringValue(Object? value) {
  return value?.toString().trim() ?? '';
}
