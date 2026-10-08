import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/material_scope_store.dart';
import '../domain/library_model.dart';
import '../domain/material_chapters.dart';

Future<bool> showMaterialChapterPicker(
    BuildContext context, LibraryFile file) async {
  List<MaterialChapter>? saved;
  String? warning;
  try {
    saved = await MaterialScopeStore().load(file);
  } catch (error) {
    warning = error.toString().replaceFirst('Bad state: ', '');
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(
          context: context,
          builder: (_) =>
              _ChapterDialog(file: file, saved: saved, warning: warning)) ??
      false;
}

class MaterialChapterButton extends StatefulWidget {
  const MaterialChapterButton({super.key, required this.file});
  final LibraryFile file;
  @override
  State<MaterialChapterButton> createState() => _MaterialChapterButtonState();
}

class _MaterialChapterButtonState extends State<MaterialChapterButton> {
  late Future<List<MaterialChapter>?> _saved;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(MaterialChapterButton old) {
    super.didUpdateWidget(old);
    if (old.file.id != widget.file.id ||
        old.file.conteudo != widget.file.conteudo) {
      _refresh();
    }
  }

  void _refresh() {
    _saved = MaterialScopeStore().load(widget.file);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<MaterialChapter>?>(
      future: _saved,
      builder: (context, snapshot) =>
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextButton.icon(
                onPressed: () async {
                  if (await showMaterialChapterPicker(context, widget.file) &&
                      mounted) {
                    setState(_refresh);
                  }
                },
                icon: const Icon(Icons.checklist),
                label: const Text('Selecionar capítulos')),
            Text(
                snapshot.hasError
                    ? 'Revise a seleção deste material'
                    : snapshot.data == null
                        ? 'Documento inteiro'
                        : '${snapshot.data!.length} capítulo(s)/trecho(s) selecionado(s)',
                style: Theme.of(context).textTheme.bodySmall),
          ]));
}

class _ChapterDialog extends StatefulWidget {
  const _ChapterDialog({required this.file, this.saved, this.warning});
  final LibraryFile file;
  final List<MaterialChapter>? saved;
  final String? warning;
  @override
  State<_ChapterDialog> createState() => _ChapterDialogState();
}

class _ChapterDialogState extends State<_ChapterDialog> {
  late final List<MaterialChapter> _chapters;
  late final List<String> _lines;
  final Set<int> _selected = {};
  final _start = TextEditingController(text: '1');
  final _end = TextEditingController();
  final _search = TextEditingController();
  bool _manual = false;
  bool _busy = false;
  String? _error;
  int? _foundLine;
  @override
  void initState() {
    super.initState();
    _chapters = detectMaterialChapters(widget.file.conteudo);
    _lines = widget.file.conteudo.split('\n');
    _end.text = '${_lines.length}';
    _error = widget.warning;
    if (widget.saved == null && widget.warning == null) {
      _selected.addAll(List.generate(_chapters.length, (i) => i));
    } else if (widget.saved != null) {
      for (var i = 0; i < _chapters.length; i++) {
        if (widget.saved!.any(
            (s) => s.start == _chapters[i].start && s.end == _chapters[i].end)) {
          _selected.add(i);
        }
      }
      if (_selected.isEmpty && widget.saved!.length == 1) {
        _manual = true;
        final range = widget.saved!.single;
        var pos = 0;
        for (var i = 0; i < _lines.length; i++) {
          if (pos == range.start) _start.text = '${i + 1}';
          pos += _lines[i].length + 1;
          if (pos >= range.end) {
            _end.text = '${i + 1}';
            break;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _search.dispose();
    super.dispose();
  }

  MaterialChapter _manualRange() {
    final first = int.tryParse(_start.text);
    final last = int.tryParse(_end.text);
    if (first == null ||
        last == null ||
        first < 1 ||
        last < first ||
        last > _lines.length) {
      throw ArgumentError('Informe linhas válidas entre 1 e ${_lines.length}.');
    }
    var start = 0;
    for (var i = 0; i < first - 1; i++) {
      start += _lines[i].length + 1;
    }
    var end = start;
    for (var i = first - 1; i < last; i++) {
      end += _lines[i].length + 1;
    }
    return MaterialChapter(
        title: 'Trecho: linhas $first a $last',
        start: start,
        end: math.min(end, widget.file.conteudo.length));
  }

  Future<void> _save({bool whole = false}) async {
    setState(() => _busy = true);
    try {
      final store = MaterialScopeStore();
      if (whole) {
        await store.clear(widget.file);
      } else {
        await store.save(
            widget.file,
            _manual
                ? [_manualRange()]
                : _selected.map((i) => _chapters[i]).toList());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error
            .toString()
            .replaceFirst('Invalid argument(s): ', '')
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Capítulos para estudar'),
        content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text(
                      'A escolha vale para resumos e questões. O PDF original permanece completo.'),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Definir trecho por linhas'),
                      value: _manual,
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _manual = value)),
                  if (!_manual) ...[
                    if (_chapters.length == 1 &&
                        _chapters.first.title == 'Documento inteiro')
                      const Text(
                          'Não identifiquei capítulos claros. Use o intervalo de linhas para marcar o trecho desejado.'),
                    Wrap(children: [
                      TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _selected.addAll(
                                  List.generate(_chapters.length, (i) => i))),
                          child: const Text('Marcar todos')),
                      TextButton(
                          onPressed:
                              _busy ? null : () => setState(_selected.clear),
                          child: const Text('Desmarcar todos'))
                    ]),
                    for (var i = 0; i < _chapters.length; i++)
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_chapters[i].title),
                          subtitle: Text(
                              widget.file.conteudo.substring(
                                  _chapters[i].start,
                                  math.min(_chapters[i].end,
                                      _chapters[i].start + 220)),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis),
                          value: _selected.contains(i),
                          onChanged: _busy
                              ? null
                              : (checked) => setState(() => checked == true
                                  ? _selected.add(i)
                                  : _selected.remove(i))),
                  ] else ...[
                    Text(
                        'Texto extraído: ${_lines.length} linhas. Os números se referem ao texto, não às páginas do PDF.'),
                    TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                            labelText: 'Buscar título ou palavra no texto'),
                        onChanged: (value) => setState(() => _foundLine =
                            value.trim().isEmpty
                                ? null
                                : _lines.indexWhere((l) => l
                                    .toLowerCase()
                                    .contains(value.trim().toLowerCase())))),
                    if (_foundLine != null) ...[
                      Text(_foundLine! < 0
                          ? 'Não encontrado'
                          : 'Linha ${_foundLine! + 1}: ${_lines[_foundLine!]}'),
                      if (_foundLine! >= 0)
                        Wrap(children: [
                          TextButton(
                              onPressed: () => setState(
                                  () => _start.text = '${_foundLine! + 1}'),
                              child: const Text('Usar como início')),
                          TextButton(
                              onPressed: () => setState(
                                  () => _end.text = '${_foundLine! + 1}'),
                              child: const Text('Usar como fim'))
                        ]),
                    ],
                    TextField(
                        controller: _start,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Linha inicial'),
                        onChanged: (_) => setState(() {})),
                    TextField(
                        controller: _end,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Linha final (incluída)'),
                        onChanged: (_) => setState(() {})),
                    const SizedBox(height: 12),
                    const Text('Prévia do trecho'),
                    Builder(builder: (context) {
                      try {
                        final r = _manualRange();
                        final t =
                            widget.file.conteudo.substring(r.start, r.end);
                        return SelectableText(t.length > 2000
                            ? '${t.substring(0, 2000)}\n… prévia abreviada'
                            : t);
                      } catch (_) {
                        return const Text(
                            'Ajuste o intervalo para visualizar.');
                      }
                    }),
                  ],
                ]))),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: _busy ? null : () => _save(whole: true),
              child: const Text('Usar documento inteiro')),
          FilledButton(
              onPressed: _busy ? null : () => _save(),
              child: Text(_busy ? 'Salvando…' : 'Aplicar seleção'))
        ],
      );
}
