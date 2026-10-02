import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long topic preserves explanation width on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final question = Question.fromJson({
      'id': 'layout',
      'text': 'Qual alternativa está correta?',
      'options': [
        {'id': 'a', 'text': 'Alternativa correta'},
        {'id': 'b', 'text': 'Outra alternativa'},
      ],
      'correct_answer': 'A',
      'topic':
          'Administração pública e organização dos poderes constitucionais',
      'explanation':
          'Uma justificativa longa deve usar a largura disponível e permanecer legível abaixo da resposta correta.',
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      home: QuizSessionScreen(questions: [question]),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Alternativa correta'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester.getSize(find.text('Você acertou! Explicação do Assunto')).width,
        greaterThan(180));
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
      expect(find.textContaining('Resposta correta'), findsWidgets);
      expect(
        find.textContaining('Gerenciar o orcamento pessoal e familiar'),
        findsWidgets,
      );
    },
  );

  testWidgets(
    'marks correct option when backend sends current camelCase payload',
    (tester) async {
      final question = Question.fromJson({
        'id': 'q_backend',
        'text': 'O que e educacao financeira?',
        'options': [
          {
            'id': 'opt_0_0',
            'text': 'Aprender a investir em acoes',
            'isCorrect': false,
          },
          {
            'id': 'opt_0_1',
            'text': 'Gerenciar o orcamento pessoal e familiar',
            'isCorrect': true,
          },
          {
            'id': 'opt_0_2',
            'text': 'Estudar a teoria economica',
            'isCorrect': false,
          },
          {
            'id': 'opt_0_3',
            'text': 'Fazer contabilidade empresarial',
            'isCorrect': false,
          },
        ],
        'correctOptionId': 'opt_0_1',
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

      expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
      expect(find.textContaining('Resposta correta'), findsWidgets);
      expect(
        find.textContaining('Gerenciar o orcamento pessoal e familiar'),
        findsWidgets,
      );
    },
  );
}
