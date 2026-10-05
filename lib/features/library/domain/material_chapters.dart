class MaterialChapter {
  const MaterialChapter(
      {required this.title, required this.start, required this.end});
  final String title;
  final int start;
  final int end;
  Map<String, dynamic> toJson() => {'title': title, 'start': start, 'end': end};
  factory MaterialChapter.fromJson(Map<String, dynamic> json) =>
      MaterialChapter(
          title: json['title'] as String,
          start: json['start'] as int,
          end: json['end'] as int);
}

List<MaterialChapter> detectMaterialChapters(String text) {
  if (text.trim().isEmpty) return [];
  final heading = RegExp(
      r'^(?:cap[ií]tulo|chapter|unidade|m[oó]dulo|parte)\s+(?:\d+|[ivxlcdm]+)\b',
      caseSensitive: false);
  final starts = <({String title, int offset})>[];
  var offset = 0;
  for (final line in text.split('\n')) {
    final title = line.trim();
    if (title.length <= 180 &&
        heading.hasMatch(title) &&
        !RegExp(r'\.{3,}\s*\d+\s*$').hasMatch(title)) {
      starts.add((title: title, offset: offset));
    }
    offset += line.length + 1;
  }
  if (starts.isEmpty) {
    return [
      MaterialChapter(title: 'Documento inteiro', start: 0, end: text.length)
    ];
  }
  final result = <MaterialChapter>[];
  if (starts.first.offset > 0 &&
      text.substring(0, starts.first.offset).trim().isNotEmpty) {
    result.add(MaterialChapter(
        title: 'Introdução e páginas iniciais',
        start: 0,
        end: starts.first.offset));
  }
  for (var i = 0; i < starts.length; i++) {
    result.add(MaterialChapter(
        title: starts[i].title,
        start: starts[i].offset,
        end: i + 1 < starts.length ? starts[i + 1].offset : text.length));
  }
  return result;
}

String extractSelectedChapters(String text, List<MaterialChapter> chapters) {
  if (chapters.isEmpty) {
    throw ArgumentError('Selecione pelo menos um capítulo ou trecho.');
  }
  final ordered = [...chapters]..sort((a, b) => a.start.compareTo(b.start));
  var previousEnd = 0;
  for (final chapter in ordered) {
    if (chapter.start < previousEnd ||
        chapter.end <= chapter.start ||
        chapter.end > text.length) {
      throw ArgumentError('Intervalo de conteúdo inválido.');
    }
    previousEnd = chapter.end;
  }
  final selected = ordered
      .map((c) => text.substring(c.start, c.end).trim())
      .where((s) => s.isNotEmpty)
      .join('\n\n');
  if (selected.isEmpty) {
    throw ArgumentError('O trecho selecionado não contém texto.');
  }
  return selected;
}
