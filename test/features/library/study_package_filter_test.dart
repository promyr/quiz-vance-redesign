import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/library/domain/study_package_filter.dart';

void main() {
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

    test('removes flashcards and questions about metadata', () {
      final package = StudyPackage(
        titulo: 'Comportamento Organizacional',
        resumoCurto: 'Resumo valido.',
        topicosPrincipais: const [
          'Motivacao no trabalho',
          'ISBN e ficha catalografica',
        ],
        flashcards: const [
          {
            'front': 'O que e motivacao no trabalho?',
            'back': 'E a energia que orienta o comportamento profissional.',
          },
          {
            'front': 'Qual e o ISBN do livro?',
            'back': '978-85-0000-000-0',
          },
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
      expect(sanitized.flashcards, hasLength(1));
      expect(sanitized.flashcards.first['front'], contains('motivacao'));
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
        flashcards: const [
          {
            'front': 'O que e tipicidade?',
            'back': 'E a adequacao da conduta ao tipo penal.',
          },
        ],
        questoes: const [],
        checklistEstudo: const ['Revisar conceitos basicos'],
      );

      final sanitized = sanitizeStudyPackageForMaterial(
        package: package,
        file: manualFile,
      );

      expect(sanitized.flashcards, hasLength(1));
      expect(sanitized.topicosPrincipais, ['Tipicidade']);
    });
  });
}
