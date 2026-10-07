import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';

void main() {
  test('mentioned or identical premises retain labels in both columns', () {
    final question = Question.fromJson({
      'text': 'Associe água e gelo.',
      'association': {
        'left': [
          {'id': 'I', 'text': 'água'},
          {'id': 'II', 'text': 'gelo'},
        ],
        'right': [
          {'id': '1', 'text': 'água'},
          {'id': '2', 'text': 'gelo'},
        ],
      },
    });
    expect(question.text, contains('Coluna I\nI — água\nII — gelo'));
    expect(question.text, contains('Coluna II\n1 — água\n2 — gelo'));
    expect(Question.fromJson(question.toJson()).text, question.text);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('quiz displays both association columns before the answer',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final question = Question.fromJson({
      'id': 'association-ui',
      'text': 'Associe as colunas.',
      'association': {
        'left': [
          {'id': 'I', 'text': 'Evaporação'},
          {'id': 'II', 'text': 'Condensação'},
        ],
        'right': [
          {'id': '1', 'text': 'Líquido para gás'},
          {'id': '2', 'text': 'Gás para líquido'},
        ],
      },
      'options': [
        {'id': 'a', 'text': 'I-1; II-2'},
        {'id': 'b', 'text': 'I-2; II-1'},
      ],
      'correct_option_id': 'a',
      'explanation':
          'Evaporação transforma líquido em gás; condensação faz o inverso.',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: QuizSessionScreen(questions: [question]),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('I — Evaporação'), findsOneWidget);
    expect(find.textContaining('2 — Gás para líquido'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('I-1; II-2'));
    await tester.tap(find.text('I-1; II-2'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('association premises are visible and survive session serialization',
      () {
    final question = Question.fromJson({
      'id': 'association-1',
      'text': 'Associe as colunas.',
      'association': {
        'left': [
          {'id': 'I', 'text': 'Evaporação'},
          {'id': 'II', 'text': 'Condensação'},
        ],
        'right': [
          {'id': '1', 'text': 'Líquido para gás'},
          {'id': '2', 'text': 'Gás para líquido'},
        ],
      },
      'options': [
        {'id': 'a', 'text': 'I-1; II-2'},
        {'id': 'b', 'text': 'I-2; II-1'},
      ],
      'correct_option_id': 'a',
    });
    expect(question.text, contains('I — Evaporação'));
    expect(question.text, contains('2 — Gás para líquido'));
    final recovered = Question.fromJson(question.toJson());
    expect(recovered.text, question.text);
    expect(recovered.correctOptionId, 'a');
  });

  test('propositions from provider aliases are included without duplication',
      () {
    final question = Question.fromJson({
      'text': 'Avalie as proposições.',
      'proposicoes': [
        {'id': 'I', 'texto': 'O calor é energia.'},
        {'id': 'II', 'texto': 'O gelo é sólido.'},
      ],
    });
    expect(question.text, contains('I — O calor é energia.'));
    expect(Question.fromJson(question.toJson()).text, question.text);
  });
}
