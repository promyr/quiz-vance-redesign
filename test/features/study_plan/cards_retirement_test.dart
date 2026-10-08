import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';

void main() {
  test('legacy card sessions migrate to quiz without losing the plan', () {
    expect(StudyRecommendedMode.fromString('FLASHCARDS'),
        StudyRecommendedMode.quiz);
    expect(StudyRecommendedMode.fromString('READING'),
        StudyRecommendedMode.reading);
  });
  test('legacy package cards are ignored while study content survives', () {
    final package = StudyPackage.fromJson({
      'titulo': 'Frações',
      'resumo_curto': 'Resumo',
      'topicos_principais': ['Frações'],
      'sugestoes_questoes': [],
      'checklist_de_estudo': ['Estudar frações'],
      'sugestoes_flashcards': [
        {'frente': 'Antigo', 'verso': 'Dado'}
      ],
    });
    expect(package.titulo, 'Frações');
    expect(package.checklistEstudo, ['Estudar frações']);
    expect(package.toJson().containsKey('sugestoes_flashcards'), isFalse);
  });
}
