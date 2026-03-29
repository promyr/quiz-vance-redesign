// test/app/router_safe_cast_test.dart
//
// Testa o comportamento do cast seguro usado no router para converter a lista
// de questões passada via GoRouter.extra.
//
// Antes da correção: List<Question>.from(...) lançava TypeError se algum item
// não fosse do tipo Question.
// Após a correção: .whereType<Question>().toList() filtra silenciosamente.

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';

// ─── Replica da lógica de cast do router ─────────────────────────────────────

List<Question> _safeCastQuestions(dynamic raw) {
  return (raw as List<dynamic>? ?? const []).whereType<Question>().toList();
}

Question _makeQuestion(String id) => Question(
      id: id,
      text: 'Pergunta $id',
      options: const [],
      correctOptionId: 'opt_1',
    );

void main() {
  group('Router – cast seguro de questões via whereType<Question>()', () {
    test('null retorna lista vazia (não lança exceção)', () {
      expect(_safeCastQuestions(null), isEmpty);
    });

    test('lista vazia retorna lista vazia', () {
      expect(_safeCastQuestions(<dynamic>[]), isEmpty);
    });

    test('lista com objetos Question corretos é preservada', () {
      final questions = [_makeQuestion('1'), _makeQuestion('2')];
      final result = _safeCastQuestions(questions);
      expect(result, hasLength(2));
      expect(result[0].id, equals('1'));
      expect(result[1].id, equals('2'));
    });

    test('lista com tipos misturados filtra apenas Question', () {
      final mixed = <dynamic>[
        _makeQuestion('1'),
        'string inesperada',
        42,
        null,
        _makeQuestion('2'),
        {'id': 'mapa_nao_e_question'},
      ];
      final result = _safeCastQuestions(mixed);
      expect(result, hasLength(2));
      expect(result, everyElement(isA<Question>()));
    });

    test('lista com apenas tipos inválidos retorna vazia (sem crash)', () {
      final invalid = <dynamic>['texto', 123, true, null, {}];
      expect(_safeCastQuestions(invalid), isEmpty);
    });

    test('List<Question>.from lançaria TypeError com tipos misturados', () {
      // Demonstra o bug original que whereType corrige
      final mixed = <dynamic>[_makeQuestion('1'), 'string_invalida'];
      expect(
        () => List<Question>.from(mixed),
        throwsA(isA<TypeError>()),
      );
    });

    test('whereType nunca lança exceção mesmo com tipos arbitrários', () {
      final arbitrary = <dynamic>[Object(), [], {}, 3.14, false];
      expect(() => _safeCastQuestions(arbitrary), returnsNormally);
      expect(_safeCastQuestions(arbitrary), isEmpty);
    });

    test('preserva ordem dos elementos válidos', () {
      final questions = List.generate(5, (i) => _makeQuestion('q$i'));
      final result = _safeCastQuestions(questions);
      for (var i = 0; i < result.length; i++) {
        expect(result[i].id, equals('q$i'));
      }
    });
  });

  group('GoRouter extra Map – acesso seguro a chaves', () {
    test('extra null retorna null sem cast exception', () {
      const Map<String, dynamic>? extra = null;
      final questions = extra?['questions'] as List<dynamic>?;
      expect(questions, isNull);
    });

    test('extra com questions presente retorna lista corretamente', () {
      final q = _makeQuestion('1');
      final Map<String, dynamic> extra = {'questions': <Question>[q]};
      final rawList = extra['questions'] as List<dynamic>?;
      final result = (rawList ?? const []).whereType<Question>().toList();
      expect(result, hasLength(1));
    });

    test('extra sem chave questions retorna lista vazia', () {
      final Map<String, dynamic> extra = {'other_key': 'value'};
      final rawList = extra['questions'] as List<dynamic>?;
      final result = (rawList ?? const []).whereType<Question>().toList();
      expect(result, isEmpty);
    });
  });
}
