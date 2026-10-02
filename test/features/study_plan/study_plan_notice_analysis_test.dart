import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_notice_analysis.dart';

void main() {
  test('parses structured subjects and exposes grounded plan topics', () {
    final analysis = StudyPlanNoticeAnalysis.fromJson({
      'cargo_encontrado': 'Analista Judiciário - TI',
      'disciplinas': [
        {
          'nome': 'Banco de Dados',
          'topicos': ['SQL', 'Normalização'],
          'evidencia': 'Banco de Dados: SQL e normalização.',
        },
      ],
    });

    expect(analysis.jobTitle, 'Analista Judiciário - TI');
    expect(analysis.subjects.single.name, 'Banco de Dados');
    expect(
      analysis.planTopics,
      ['Banco de Dados: SQL', 'Banco de Dados: Normalização'],
    );
  });

  test('ignores malformed subjects without topics', () {
    final analysis = StudyPlanNoticeAnalysis.fromJson({
      'cargo_encontrado': 'Analista',
      'disciplinas': [
        {'nome': 'Vazio', 'topicos': <String>[]},
        'inválido',
      ],
    });

    expect(analysis.subjects, isEmpty);
    expect(analysis.planTopics, isEmpty);
  });
}
