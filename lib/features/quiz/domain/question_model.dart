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

/// Metadados da fonte da questão (apostila/documento da biblioteca).
class QuestionSource {
  const QuestionSource({
    this.document,
    this.documentId,
    this.chapter,
    this.section,
    this.page,
    this.topic,
    this.excerpt,
  });

  factory QuestionSource.fromJson(Map<String, dynamic> json) => QuestionSource(
        document: json['document']?.toString(),
        documentId: (json['document_id'] as num?)?.toInt() ??
            (json['documentId'] as num?)?.toInt(),
        chapter: json['chapter']?.toString(),
        section: json['section']?.toString(),
        page: (json['page'] as num?)?.toInt(),
        topic: json['topic']?.toString(),
        excerpt:
            json['excerpt']?.toString() ?? json['trecho_fonte']?.toString(),
      );

  /// Nome do documento/apostila de onde a questão foi extraída.
  final String? document;

  /// ID opcional do documento no backend para navegação direta.
  final int? documentId;

  /// Capítulo no documento.
  final String? chapter;

  /// Seção no documento.
  final String? section;

  /// Número da página.
  final int? page;

  /// Tópico específico de onde o trecho foi retirado.
  final String? topic;

  /// Trecho literal do documento que embasou a questão.
  final String? excerpt;

  /// Verdadeiro quando há pelo menos um campo com dado útil.
  bool get hasData =>
      (document?.trim().isNotEmpty ?? false) ||
      (excerpt?.trim().isNotEmpty ?? false) ||
      (chapter?.trim().isNotEmpty ?? false) ||
      (section?.trim().isNotEmpty ?? false) ||
      page != null;

  Map<String, dynamic> toJson() => {
        'document': document,
        'document_id': documentId,
        'chapter': chapter,
        'section': section,
        'page': page,
        'topic': topic,
        'excerpt': excerpt,
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
    this.source,
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
    final rawSource = json['source'];
    return Question(
      id: json['id']?.toString() ?? '',
      text: _completeQuestionText(json),
      options: options,
      correctOptionId: _resolveCorrectOptionId(
        rawCorrect: rawCorrect,
        options: options,
      ),
      explanation:
          json['explanation']?.toString() ?? json['explicacao']?.toString(),
      topic: json['topic']?.toString() ?? json['subtema']?.toString(),
      difficulty: json['difficulty']?.toString() ?? 'medium',
      source: rawSource is Map<String, dynamic>
          ? QuestionSource.fromJson(rawSource)
          : null,
    );
  }

  final String id;
  final String text;
  final List<QuizOption> options;
  final String correctOptionId;
  final String? explanation;
  final String? topic;
  final String difficulty;

  /// Metadados da fonte — presente apenas em questões geradas a partir de
  /// um documento da biblioteca. Null quando gerada via tópico livre.
  final QuestionSource? source;

  QuizOption? get correctOption {
    for (final option in options) {
      if (option.id == correctOptionId) {
        return option;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'options': options.map((e) => e.toJson()).toList(),
        'correct_option_id': correctOptionId,
        'explanation': explanation,
        'topic': topic,
        'difficulty': difficulty,
        if (source != null) 'source': source!.toJson(),
      };

  String? get correctOptionLetter {
    final index = options.indexWhere((option) => option.id == correctOptionId);
    if (index < 0) {
      return null;
    }
    return String.fromCharCode(65 + index);
  }

  String getEffectiveExplanation([String? fallbackTopic]) {
    final exp = explanation?.trim();
    if (exp != null && exp.isNotEmpty) {
      return exp;
    }
    final topicName = (topic?.trim().isNotEmpty == true)
        ? topic!.trim()
        : (fallbackTopic?.trim().isNotEmpty == true
            ? fallbackTopic!.trim()
            : 'deste assunto');
    final letter = correctOptionLetter;
    final optText = correctOption?.text.trim() ?? '';
    if (letter != null && optText.isNotEmpty) {
      return 'A alternativa correta é a letra $letter ($optText). Esta resposta sintetiza a solução adequada para as questões sobre $topicName.';
    } else if (optText.isNotEmpty) {
      return 'A alternativa correta é: $optText. Conceito essencial para a compreensão de $topicName.';
    }
    return 'Gabarito oficial correspondente aos tópicos fundamentais de $topicName.';
  }
}

/// Keep association columns and assertions in the statement. All quiz,
/// simulation and review screens already render this statement, including
/// restored offline sessions. The canonical backend also flattens these fields;
/// checking complete labeled blocks avoids duplicating the canonical response.
String _completeQuestionText(Map<String, dynamic> json) {
  var text =
      (json['text'] ?? json['question'] ?? json['pergunta'] ?? '').toString();
  final association = json['association'];
  final columns = association is Map ? association : const <String, dynamic>{};
  final sections = <String, dynamic>{
    'Coluna I': json['coluna_esquerda'] ?? columns['left'],
    'Coluna II': json['coluna_direita'] ?? columns['right'],
    'Proposições': json['proposicoes'] ?? json['propositions'],
  };
  for (final section in sections.entries) {
    final raw = section.value;
    if (raw is! List || raw.isEmpty) continue;
    final lines = <String>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      final content =
          (item is Map ? item['text'] ?? item['texto'] ?? '' : item ?? '')
              .toString()
              .trim();
      if (content.isEmpty) continue;
      final label = item is Map
          ? (item['id'] ?? item['label'] ?? '${i + 1}').toString()
          : '${i + 1}';
      lines.add('$label — $content');
    }
    final block = '${section.key}\n${lines.join('\n')}';
    if (lines.isNotEmpty && !text.contains(block)) {
      text += '\n\n$block';
    }
  }
  return text;
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
  final prefixedNumber = RegExp(r'^(\d+)[\)\].:\-\s]+').firstMatch(normalized);
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
    final nestedId =
        value['id'] ?? value['option_id'] ?? value['correctOptionId'];
    if (nestedId != null) {
      return nestedId.toString().trim();
    }
    final nestedText =
        value['text'] ?? value['answer'] ?? value['correct_answer'];
    if (nestedText != null) {
      return nestedText.toString().trim();
    }
  }
  return value?.toString().trim() ?? '';
}
