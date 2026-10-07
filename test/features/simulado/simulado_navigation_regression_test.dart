import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/simulado/presentation/simulado_screen.dart';
import 'package:quiz_vance_flutter/features/simulado/presentation/simulado_review_screen.dart';
import 'package:quiz_vance_flutter/features/simulado/presentation/simulado_config_screen.dart';
import 'package:quiz_vance_flutter/features/simulado/data/simulado_recovery_store.dart';

Question q(String text) => Question(
    id: text,
    text: text,
    options: const [
      QuizOption(id: 'a', text: 'Correta'),
      QuizOption(id: 'b', text: 'Errada')
    ],
    correctOptionId: 'a',
    explanation: 'Justificativa longa. ' * 160);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('configuração mantida atualiza retomada ao sair da sessão',
      (tester) async {
    final router = GoRouter(initialLocation: '/simulado', routes: [
      GoRoute(path: '/simulado', builder: (_, __) => const SimuladoConfigScreen(),
          routes: [GoRoute(path: 'session', name: 'simuladoSession',
              builder: (_, state) => SimuladoScreen(
                  questions: [q('Questão ida'), q('Questão volta')],
                  durationSeconds: 600,
                  checkpoint: (state.extra as Map?)?['checkpoint']))]),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Retomar simulado'), findsNothing);
    router.pushNamed('simuladoSession');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correta'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sair'));
    await tester.pumpAndSettle();
    expect(find.text('Retomar simulado'), findsOneWidget);
    await tester.tap(find.text('Retomar simulado'));
    await tester.pumpAndSettle();
    expect(find.text('Questão ida'), findsOneWidget);
    expect((await SimuladoRecoveryStore().load())!.answers[0], 'a');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await SimuladoRecoveryStore().load();
  });
  testWidgets('retomar da configuração conserva tentativa sem pedir geração',
      (tester) async {
    final checkpoint = SimuladoCheckpoint(
        sessionId: 'saved',
        questions: [q('Questão salva')],
        durationSeconds: 600,
        startedAt: DateTime.now(),
        answers: {0: 'a'});
    await SimuladoRecoveryStore().save(checkpoint);
    SimuladoCheckpoint? received;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const SimuladoConfigScreen()),
      GoRoute(
          path: '/session',
          name: 'simuladoSession',
          builder: (_, state) {
            received = (state.extra as Map)['checkpoint'];
            return const Text('Tentativa retomada');
          }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text('Retomar simulado'), findsOneWidget);
    await tester.tap(find.text('Retomar simulado'));
    await tester.pumpAndSettle();
    expect(received!.sessionId, 'saved');
    expect(received!.answers[0], 'a');
  });
  testWidgets('Voltar Android oferece continuar sem perder resposta',
      (tester) async {
    final router = GoRouter(initialLocation: '/session', routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('Inicio')),
      GoRoute(
          path: '/session',
          builder: (_, __) => SimuladoScreen(
              questions: [q('Questão um'), q('Questão dois')],
              durationSeconds: 600)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correta'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sair do simulado?'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Questão um'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('próximo erro começa com rolagem no topo', (tester) async {
    final result = QuizResult(
        sessionId: 'review',
        total: 2,
        correct: 0,
        xpEarned: 0,
        timeTaken: Duration.zero,
        answers: [
          for (final text in ['Primeira questão', 'Segunda questão'])
            QuestionAnswer(
                question: q(text), selectedOptionId: 'b', isCorrect: false)
        ]);
    await tester
        .pumpWidget(MaterialApp(home: SimuladoReviewScreen(result: result)));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1800));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0));
    await tester.tap(find.text('Próximo erro'));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    expect(find.text('Segunda questão').hitTestable(), findsOneWidget);
  });
}
