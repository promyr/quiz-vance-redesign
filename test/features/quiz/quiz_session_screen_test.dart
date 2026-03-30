import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'marks correct option when backend sends correct answer as letter',
    (tester) async {
      final question = Question.fromJson({
        'id': 'q_1',
        'text': 'O que e educacao financeira?',
        'options': [
          {'id': 'a', 'text': 'Aprender a investir em acoes'},
          {
            'id': 'b',
            'text': 'Gerenciar o orcamento pessoal e familiar',
          },
          {'id': 'c', 'text': 'Estudar teoria economica'},
          {'id': 'd', 'text': 'Fazer contabilidade empresarial'},
        ],
        'correct_answer': 'B',
        'explanation':
            'Educacao financeira e o processo de aprender a gerenciar o orcamento pessoal e familiar.',
        'topic': 'Educacao Financeira',
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: QuizSessionScreen(questions: [question]),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gerenciar o orcamento pessoal e familiar'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
      expect(find.text('Resposta correta'), findsOneWidget);
      expect(
        find.text('B • Gerenciar o orcamento pessoal e familiar'),
        findsOneWidget,
      );
    },
  );
}
