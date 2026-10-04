import 'package:flutter/material.dart';
import '../domain/study_plan_notice_analysis.dart';

class NoticeSubjectEditor extends StatefulWidget {
  const NoticeSubjectEditor({super.key, required this.subject});
  final StudyPlanNoticeSubject subject;
  @override
  State<NoticeSubjectEditor> createState() => _NoticeSubjectEditorState();
}

class _NoticeSubjectEditorState extends State<NoticeSubjectEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.subject.name);
  late final _topics =
      TextEditingController(text: widget.subject.topics.join('\n'));
  @override
  void dispose() {
    _name.dispose();
    _topics.dispose();
    super.dispose();
  }

  List<String> get _values {
    final values = <String, String>{};
    for (final line in _topics.text.split('\n')) {
      final value = line.replaceFirst(RegExp(r'^\s*[-•]\s*'), '').trim();
      if (value.isNotEmpty) {
        values.putIfAbsent(value.toLowerCase(), () => value);
      }
    }
    return values.values.toList();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Revisar disciplina'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Confira o que foi extraído do PDF. Escreva um tópico por linha; sua revisão será usada no plano.'),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _name,
                      maxLength: 200,
                      decoration:
                          const InputDecoration(labelText: 'Disciplina'),
                      validator: (v) => v?.trim().isNotEmpty == true
                          ? null
                          : 'Informe a disciplina'),
                  TextFormField(
                      controller: _topics,
                      minLines: 3,
                      maxLines: 8,
                      maxLength: 8000,
                      decoration: const InputDecoration(labelText: 'Tópicos'),
                      validator: (_) => _values.isEmpty
                          ? 'Informe ao menos um tópico'
                          : null),
                  if (widget.subject.evidence.isNotEmpty)
                    Text('Trecho encontrado: ${widget.subject.evidence}'),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                final original = widget.subject;
                Navigator.pop(
                    context,
                    StudyPlanNoticeSubject(
                        name: _name.text.trim(),
                        topics: _values,
                        evidence: original.evidence,
                        peso: original.peso,
                        numQuestoes: original.numQuestoes));
              },
              child: const Text('Salvar revisão'))
        ],
      );
}
