class QuizOption {
  const QuizOption({
    required this.id,
    required this.text,
    this.isCorrect = false,
  });

  factory QuizOption.fromJson(Map<String, dynamic> json) => QuizOption(
        id: json['id']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        isCorrect: (json['is_correct'] as bool?) ??
            (json['isCorrect'] as bool?) ??
            false,
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
      json['correct_option_id'] ??
          json['correctOptionId'] ??
          json['correct_answer'] ??
          json['correctAnswer'],
    );
    return Question(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ??
          json['question']?.toString() ??
          json['pergunta']?.toString() ??
          '',
      options: options,
      correctOptionId: _resolveCorrectOptionId(
        rawCorrect: rawCorrect,
        options: options,
      ),
      explanation:
          json['explanation']?.toString() ?? json['explicacao']?.toString(),
      topic: json['topic']?.toString() ?? json['subtema']?.toString(),
      difficulty: json['difficulty']?.toString() ?? 'medium',
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

  final numericIndex = _extractAnswerIndex(rawCorrect, options.length);
  if (numericIndex != null) {
    return options[numericIndex].id;
  }

  for (final option in options) {
    if (option.isCorrect) {
      return option.id;
    }
  }

  return rawCorrect;
}

String? _findOptionIdByCandidate(
  String rawCandidate,
  List<QuizOption> options,
) {
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

int? _extractAnswerIndex(String rawValue, int optionCount) {
  final normalized = _normalizeAnswer(_stripLeadingAnswerLabel(rawValue));
  if (normalized.isEmpty) {
    return null;
  }

  final directNumber = RegExp(r'^(\d+)$').firstMatch(normalized);
  final prefixedNumber =
      RegExp(r'^(\d+)[\)\].:\-\s]+').firstMatch(normalized);
  final captured = directNumber?.group(1) ?? prefixedNumber?.group(1);
  if (captured == null) {
    return null;
  }

  final parsed = int.tryParse(captured);
  if (parsed == null) {
    return null;
  }

  final oneBased = parsed - 1;
  if (oneBased >= 0 && oneBased < optionCount) {
    return oneBased;
  }

  if (parsed >= 0 && parsed < optionCount) {
    return parsed;
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
      .replaceFirst(
        RegExp(r'^\d+[\)\].:\-\s]+', caseSensitive: false),
        '',
      )
      .trim();
}

String _stripLeadingAnswerLabel(String rawValue) {
  return _normalizeAnswer(rawValue).replaceFirst(
    RegExp(
      r'^(resposta correta|resposta|alternativa|opcao|opção|letra)\s*[:\-]?\s+',
      caseSensitive: false,
    ),
    '',
  );
}

String _normalizeAnswer(String value) {
  final lowered = value.trim().toLowerCase();
  final withoutAccents = _stripDiacritics(lowered);
  return withoutAccents
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll('`', '')
      .replaceAll('´', '')
      .replaceAll('“', '')
      .replaceAll('”', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _stripDiacritics(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}

String _stringValue(Object? value) {
  if (value is Map<String, dynamic>) {
    final nestedId = value['id'] ?? value['option_id'] ?? value['correctOptionId'];
    if (nestedId != null) {
      return nestedId.toString().trim();
    }
    final nestedText = value['text'] ?? value['answer'] ?? value['correct_answer'];
    if (nestedText != null) {
      return nestedText.toString().trim();
    }
  }
  return value?.toString().trim() ?? '';
}
