import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/content/study_material_sanitizer.dart';

void main() {
  group('sanitizeStudyMaterialForPrompt', () {
    test('removes common metadata and table of contents lines', () {
      const raw = '''
ISBN 978-85-0000-000-0
Todos os direitos reservados.
Editora Exemplo
SUMARIO
Introducao ................ 3
Capitulo 1 ................ 7

Fotossintese e o processo pelo qual plantas convertem luz em energia.
Ela depende de agua, luz e dioxido de carbono.
''';

      final cleaned = sanitizeStudyMaterialForPrompt(raw);

      expect(cleaned, isNot(contains('ISBN')));
      expect(cleaned, isNot(contains('Todos os direitos reservados')));
      expect(cleaned, isNot(contains('SUMARIO')));
      expect(cleaned, contains('Fotossintese'));
      expect(cleaned, contains('luz em energia'));
    });

    test('removes repeated short headers and page markers', () {
      const raw = '''
Biologia Basica
Pagina 1
Biologia Basica
Citologia estuda a celula.
Biologia Basica
Pagina 2
A membrana plasmaticas regula trocas com o meio.
''';

      final cleaned = sanitizeStudyMaterialForPrompt(raw);

      expect(cleaned, isNot(contains('Pagina 1')));
      expect(cleaned, isNot(contains('Pagina 2')));
      expect(cleaned, contains('Citologia estuda a celula.'));
      expect(cleaned,
          contains('A membrana plasmaticas regula trocas com o meio.'));
    });

    test('respects maxChars after cleaning', () {
      final raw = 'Conteudo util ' * 1000;

      final cleaned = sanitizeStudyMaterialForPrompt(raw, maxChars: 120);

      expect(cleaned.length, lessThanOrEqualTo(120));
      expect(cleaned, contains('Conteudo util'));
    });

    test('removes DOI and copyright lines', () {
      const raw = '''
DOI: 10.1234/abc
Copyright 2024 Editora XYZ.
All rights reserved.
A mitose e o processo de divisao celular.
''';

      final cleaned = sanitizeStudyMaterialForPrompt(raw);

      expect(cleaned, isNot(contains('DOI')));
      expect(cleaned, isNot(contains('Copyright')));
      expect(cleaned, isNot(contains('All rights reserved')));
      expect(cleaned, contains('mitose'));
    });

    test('removes www and https links', () {
      const raw = '''
Acesse www.editora.com.br para mais informacoes.
https://loja.editora.com.br/livro
Neuronio e a unidade funcional do sistema nervoso.
''';

      final cleaned = sanitizeStudyMaterialForPrompt(raw);

      expect(cleaned, isNot(contains('www.')));
      expect(cleaned, isNot(contains('https')));
      expect(cleaned, contains('Neuronio'));
    });

    test('returns original trimmed content when everything is filtered out',
        () {
      const raw = 'Conteudo valido sem metadados.';
      final cleaned = sanitizeStudyMaterialForPrompt(raw);
      expect(cleaned, equals('Conteudo valido sem metadados.'));
    });

    test('handles empty string input', () {
      final cleaned = sanitizeStudyMaterialForPrompt('');
      expect(cleaned, isEmpty);
    });

    test('handles string with only metadata', () {
      const raw = 'ISBN 1234\nCopyright 2024\nDOI abc';
      final cleaned = sanitizeStudyMaterialForPrompt(raw);
      expect(cleaned, isEmpty);
    });

    test('normalizes multiple blank lines to single blank line', () {
      const raw = '''
Linha 1.



Linha 2.
''';
      final cleaned = sanitizeStudyMaterialForPrompt(raw);
      expect(cleaned, isNot(contains('\n\n\n')));
      expect(cleaned, contains('Linha 1'));
      expect(cleaned, contains('Linha 2'));
    });

    test('removes front matter and bibliography blocks aggressively', () {
      const raw = '''
TITULO DA OBRA
Autor: Fulano de Tal
Editora Exemplo
3a edicao

Introducao ao comportamento organizacional.
O comportamento humano nas empresas envolve motivacao, lideranca e cultura.
Esses fatores afetam desempenho, clima e tomada de decisao.

REFERENCIAS
CHIAVENATO, Idalberto. Administracao geral e publica. Rio de Janeiro: Elsevier, 2020.
Disponivel em: www.editora.com.br
Acesso em: 10 jan. 2026.
''';

      final cleaned = sanitizeStudyMaterialForPrompt(raw);

      expect(cleaned, isNot(contains('Autor: Fulano de Tal')));
      expect(cleaned, isNot(contains('Editora Exemplo')));
      expect(cleaned, isNot(contains('REFERENCIAS')));
      expect(cleaned, isNot(contains('CHIAVENATO')));
      expect(cleaned, contains('comportamento organizacional'));
      expect(cleaned, contains('motivacao'));
    });
  });
}
