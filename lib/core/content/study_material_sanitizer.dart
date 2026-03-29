final List<RegExp> _metadataPatterns = [
  RegExp(r'\bisbn(?:-1[03])?\b'),
  RegExp(r'\bissn\b'),
  RegExp(r'\bdoi\b'),
  RegExp(r'todos os direitos reservados'),
  RegExp(r'all rights reserved'),
  RegExp(r'\bcopyright\b'),
  RegExp(r'ficha catalogr'),
  RegExp(r'cataloga'),
  RegExp(r'\bcip\b'),
  RegExp(r'\beditora\b'),
  RegExp(r'\bpublisher\b'),
  RegExp(r'\bedit(?:ion|ora)?\b'),
  RegExp(r'\bedi(?:cao|coes)\b'),
  RegExp(r'https?://'),
  RegExp(r'www\.'),
  RegExp(r'^\s*(sumario|indice|table of contents|contents)\s*$'),
  RegExp(r'referencias?(?: bibliograficas)?'),
  RegExp(r'bibliografia'),
  RegExp(r'fontes consultadas'),
  RegExp(r'catalogacao na publicacao'),
  RegExp(r'dados internacionais de catalogacao'),
  RegExp(r'projeto grafico'),
  RegExp(r'diagramacao'),
  RegExp(r'revisao tecnica'),
  RegExp(r'revisao'),
  RegExp(r'coordenacao'),
  RegExp(r'traducao'),
  RegExp(r'organizacao'),
  RegExp(r'organizador(?:a)?'),
  RegExp(r'autor(?:es)?\b'),
  RegExp(r'publicado por'),
  RegExp(r'impresso no brasil'),
];

final RegExp _pageMarkerPattern = RegExp(
  r'^\s*(?:pagina|page)?\s*\d{1,4}(?:\s*(?:/|de)\s*\d{1,4})?\s*$',
);
final RegExp _tocEntryPattern = RegExp(r'(?:\.{2,}|\u2026)\s*\d+\s*$');
final RegExp _whitespacePattern = RegExp(r'[ \t]+');
final RegExp _digitPattern = RegExp(r'\d');
final RegExp _letterPattern = RegExp(r'[A-Za-z]');
final RegExp _wordPattern = RegExp(r'[A-Za-z0-9]+');
final RegExp _referenceHeadingPattern = RegExp(
  r'^\s*(referencias?(?: bibliograficas)?|bibliografia|works cited|references|fontes consultadas)\s*:?\s*$',
);
final RegExp _referenceLinePattern = RegExp(
  r'(disponivel em|acesso em|et al\.?|https?://|www\.)',
);
final RegExp _surnameReferencePattern = RegExp(
  r'^\s*[A-Z][A-Z\s-]{2,},\s',
);

String sanitizeStudyMaterialForPrompt(
  String raw, {
  int maxChars = 4000,
}) {
  final normalized = raw
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u00A0', ' ');

  final lines = normalized
      .split('\n')
      .map((line) => line.replaceAll(_whitespacePattern, ' ').trim())
      .toList();

  final repeatedShortLines = <String, int>{};
  for (final line in lines) {
    final key = _normalizeForMatch(line);
    if (key.isNotEmpty && key.length <= 80) {
      repeatedShortLines.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
  }

  final cleanedLines = <String>[];
  var lastWasBlank = false;
  var startedContent = false;
  var skippingReferenceSection = false;

  for (final line in lines) {
    if (line.isEmpty) {
      if (skippingReferenceSection) {
        continue;
      }
      if (!lastWasBlank && cleanedLines.isNotEmpty) {
        cleanedLines.add('');
      }
      lastWasBlank = true;
      continue;
    }

    lastWasBlank = false;

    if (_referenceHeadingPattern.hasMatch(_normalizeForMatch(line))) {
      skippingReferenceSection = true;
      continue;
    }
    if (skippingReferenceSection) {
      continue;
    }
    if (!startedContent && _shouldSkipLeadingNoise(line, repeatedShortLines)) {
      continue;
    }
    if (_shouldSkipLine(line, repeatedShortLines)) {
      continue;
    }

    if (_looksLikeContentLine(line)) {
      startedContent = true;
    }
    cleanedLines.add(line);
  }

  var cleaned = cleanedLines.join('\n').trim();
  cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

  if (cleaned.length > maxChars) {
    cleaned = cleaned.substring(0, maxChars).trimRight();
  }

  return cleaned;
}

bool _shouldSkipLine(String line, Map<String, int> repeatedShortLines) {
  final normalized = _normalizeForMatch(line);

  if (_pageMarkerPattern.hasMatch(normalized)) {
    return true;
  }
  if (_tocEntryPattern.hasMatch(normalized)) {
    return true;
  }
  if ((repeatedShortLines[normalized] ?? 0) >= 3 && line.length <= 80) {
    return true;
  }
  if (_looksLikeReferenceLine(line, normalized)) {
    return true;
  }
  for (final pattern in _metadataPatterns) {
    if (pattern.hasMatch(normalized)) {
      return true;
    }
  }

  final digits = _digitPattern.allMatches(line).length;
  final letters = _letterPattern.allMatches(_normalizeForMatch(line)).length;
  if (digits >= 4 && letters <= 6 && line.length <= 60) {
    return true;
  }

  return false;
}

bool _shouldSkipLeadingNoise(String line, Map<String, int> repeatedShortLines) {
  final normalized = _normalizeForMatch(line);
  if (_looksLikeReferenceLine(line, normalized)) {
    return true;
  }
  for (final pattern in _metadataPatterns) {
    if (pattern.hasMatch(normalized)) {
      return true;
    }
  }
  if ((repeatedShortLines[normalized] ?? 0) >= 2 && line.length <= 120) {
    return true;
  }

  final words = _wordPattern.allMatches(normalized).length;
  final letters = _letterPattern.allMatches(normalized).length;
  if (words <= 5 &&
      letters <= 40 &&
      !line.contains('.') &&
      !line.contains(';')) {
    return true;
  }
  return false;
}

bool _looksLikeReferenceLine(String original, String normalized) {
  if (_referenceLinePattern.hasMatch(normalized)) {
    return true;
  }
  if (_surnameReferencePattern.hasMatch(original)) {
    return true;
  }

  final hasYear = RegExp(r'\b(19|20)\d{2}[a-z]?\b').hasMatch(normalized);
  final hasPublisherStyle =
      normalized.contains(':') || normalized.contains(';');
  return hasYear && hasPublisherStyle;
}

bool _looksLikeContentLine(String line) {
  final normalized = _normalizeForMatch(line);
  final words = _wordPattern.allMatches(normalized).length;
  final letters = _letterPattern.allMatches(normalized).length;
  return words >= 6 &&
      letters >= 24 &&
      !_looksLikeReferenceLine(line, normalized);
}

String _normalizeForMatch(String input) {
  var text = input.toLowerCase();

  const replacements = <String, String>{
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

  replacements.forEach((from, to) {
    text = text.replaceAll(from, to);
  });

  return text.replaceAll(_whitespacePattern, ' ').trim();
}
