import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/library/domain/study_package_filter.dart';

void main() {
  test('short repeated source does not authorize generic advanced topics', () {
    final file = LibraryFile(
        id: 99,
        nome: 'qa-matematica.pdf',
        categoria: 'Matematica',
        conteudo: 'Dois mais dois resulta em quatro.\n' * 12,
        criadoEm: DateTime(2026, 10, 8));
    final filtered = sanitizeStudyPackageForMaterial(
        package: StudyPackage(
            titulo: 'Matematica intermediaria',
            resumoCurto: 'Algebra, calculo e probabilidade.',
            topicosPrincipais: const [
              'Calculo diferencial',
              'Probabilidade',
              'Adicao resulta em quatro'
            ],
            questoes: const [],
            checklistEstudo: const [
              'Estudar probabilidade'
            ]),
        file: file);
    expect(filtered.topicosPrincipais, ['Adicao resulta em quatro']);
    expect(filtered.resumoCurto, contains('Dois mais dois resulta em quatro.'));
    expect(filtered.checklistEstudo, isEmpty);
  });
  group('sanitizeStudyPackageForMaterial', () {
    final file = LibraryFile(
      id: 1,
      nome: 'Comportamento Organizacional',
      categoria: 'Administracao',
      conteudo: '''
Introducao ao comportamento organizacional.
O comportamento humano nas empresas envolve motivacao, lideranca e cultura.
Esses fatores afetam desempenho, clima e tomada de decisao.
Lideres moldam normas, incentivos e colaboracao entre equipes.
      ''',
      criadoEm: DateTime(2026, 3, 26),
    );

    test('removes questions about metadata', () {
      final package = StudyPackage(
        titulo: 'Comportamento Organizacional',
        resumoCurto: 'Resumo valido.',
        topicosPrincipais: const [
          'Motivacao no trabalho',
          'ISBN e ficha catalografica',
        ],
        questoes: const [
          {
            'pergunta': 'Como a cultura organizacional afeta o clima interno?',
            'subtema': 'Cultura organizacional',
            'opcoes': ['A', 'B', 'C', 'D'],
            'correta_index': 0,
            'explicacao': 'Ela influencia comportamento e desempenho.',
          },
          {
            'pergunta': 'Quem e o autor do material?',
            'subtema': 'Metadados',
            'opcoes': ['A', 'B', 'C', 'D'],
            'correta_index': 0,
            'explicacao': 'Pergunta editorial.',
          },
        ],
        checklistEstudo: const [
          'Revisar cultura organizacional',
          'Consultar ISBN',
        ],
      );

      final sanitized = sanitizeStudyPackageForMaterial(
        package: package,
        file: file,
      );

      expect(sanitized.topicosPrincipais, ['Motivacao no trabalho']);
      expect(sanitized.questoes, hasLength(1));
      expect(
        sanitized.questoes.first['pergunta'],
        contains('cultura organizacional'),
      );
      expect(sanitized.checklistEstudo, ['Revisar cultura organizacional']);
    });

    test('keeps manual-topic style package when context is too short', () {
      final manualFile = LibraryFile(
        id: 0,
        nome: 'Direito Penal',
        categoria: 'Gerado por IA',
        conteudo: 'Topico: Direito Penal',
        criadoEm: DateTime(2026, 3, 26),
      );
      final package = StudyPackage(
        titulo: 'Direito Penal',
        resumoCurto: 'Resumo.',
        topicosPrincipais: const ['Tipicidade'],
        questoes: const [],
        checklistEstudo: const ['Revisar conceitos basicos'],
      );

      final sanitized = sanitizeStudyPackageForMaterial(
        package: package,
        file: manualFile,
      );

      expect(sanitized.topicosPrincipais, ['Tipicidade']);
    });

    test('topic-only exemption cannot be inferred from a short imported file',
        () {
      final file = LibraryFile(
          id: -91,
          nome: 'Direito Penal',
          categoria: 'Gerado por IA',
          conteudo: 'Topico: Direito Penal',
          criadoEm: DateTime(2026, 10, 8));
      expect(file.isTopicOnlyStudyMaterial, isFalse);
      final mismatched = LibraryFile(
          id: 0,
          nome: 'Direito Penal',
          categoria: 'Gerado por IA',
          conteudo: 'Topico: Biologia',
          criadoEm: DateTime(2026, 10, 8));
      expect(mismatched.isTopicOnlyStudyMaterial, isFalse);
    });

    test('preserves checklist when relevance drops all', () {
      final package = StudyPackage(
        titulo: 'Comportamento Organizacional',
        resumoCurto: 'Resumo valido.',
        topicosPrincipais: const ['Engajamento de equipes'],
        questoes: const [],
        checklistEstudo: const ['Mapear fatores de engajamento'],
      );

      final sanitized = sanitizeStudyPackageForMaterial(
        package: package,
        file: file,
      );
      expect(sanitized.checklistEstudo, package.checklistEstudo);
      expect(sanitized.toJson().containsKey('sugestoes_flashcards'), isFalse);
    });
  });
}
