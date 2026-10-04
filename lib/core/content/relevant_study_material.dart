import 'study_material_sanitizer.dart';

/// Rank bounded overlapping passages before sanitizing; distant chapters
/// can participate instead of always truncating the document introduction.
String selectRelevantStudyMaterial(String raw, String topic,
    {int maxChars = 4000}) {
  if (maxChars <= 0) return '';
  String normalize(String s) {
    const from = 'áàâãéêíóôõúüç';
    const to = 'aaaaeeiooouuc';
    var value = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      value = value.replaceAll(from[i], to[i]);
    }
    return value;
  }

  final terms = RegExp(r'[a-z0-9]{4,}')
      .allMatches(normalize(topic))
      .map((m) => m.group(0)!)
      .where((w) =>
          !{'direito', 'sobre', 'estudo', 'gerais', 'materia'}.contains(w))
      .toSet();
  final passages = <({int index, int score, String text})>[];
  for (var start = 0; start < raw.length; start += 600) {
    final end = (start + 1200).clamp(0, raw.length);
    final text = raw.substring(start, end);
    final normalized = normalize(text);
    final score = terms.where(normalized.contains).length;
    if (score > 0) passages.add((index: start, score: score, text: text));
  }
  passages.sort((a, b) {
    final rank = b.score.compareTo(a.score);
    return rank == 0 ? a.index.compareTo(b.index) : rank;
  });
  final selected = <({int index, int score, String text})>[];
  for (final passage in passages) {
    if (selected
        .every((other) => (other.index - passage.index).abs() >= 1200)) {
      selected.add(passage);
    }
    if (selected.length >= 4) break;
  }
  // Keep ranking order so the most relevant passages survive the prompt limit.
  return sanitizeStudyMaterialForPrompt(
      selected.isEmpty ? raw : selected.map((p) => p.text).join('\n\n'),
      maxChars: maxChars);
}
