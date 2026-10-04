import 'dart:async';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_recovery_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/application/study_plan_quiz_request.dart';
import 'package:quiz_vance_flutter/features/study_plan/presentation/study_plan_screen.dart';
import 'package:quiz_vance_flutter/features/study_plan/presentation/today_plan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/quiz/presentation/quiz_session_screen.dart';

class _QuizRepository extends Mock implements QuizRepository {}

class _Plans extends Mock implements StudyPlanRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final first = StudyPlanItem(
      sessionId: 'first',
      dia: 'Hoje',
      scheduledDate: DateTime.now().toIso8601String().substring(0, 10),
      subject: 'Portugues',
      tema: 'Sintaxe',
      atividade: 'Quiz',
      duracaoMin: 30,
      prioridade: 1);
  final selected = StudyPlanItem(
      sessionId: 'chosen',
      dia: 'Hoje',
      scheduledDate: DateTime.now().toIso8601String().substring(0, 10),
      subject: 'Direito',
      tema: 'Constitucional',
      subtopics: const ['Direitos fundamentais', 'Organizacao do Estado'],
      atividade: 'Quiz',
      duracaoMin: 30,
      prioridade: 1);
  final plan = StudyPlan(
      id: 'chosen-plan',
      title: 'Concurso',
      objetivo: 'Concurso',
      tempoDiario: 30,
      sourceDocumentIds: const [12],
      items: [first, selected]);

  test('pedido conserva todos os topicos e identidade da sessao escolhida', () {
    final params = studyPlanQuizRequest(plan, selected);
    expect(
        params.topic, 'Direito: Direitos fundamentais; Organizacao do Estado');
    expect(params.planId, 'chosen-plan');
    expect(params.studySessionId, 'chosen');
    expect(params.documentId, 12);
    expect(params.aiProvider, isNull);
  });

  for (final daily in [false, true]) {
    testWidgets(
        'botao real do plano envia o segundo item sem configurar (hoje $daily)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = _Plans();
      when(() => repository.listDocuments(purpose: any(named: 'purpose')))
          .thenAnswer((_) async => []);
      QuizGenerationParams? captured;
      var returned = false;
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) =>
                daily ? const TodayPlanScreen() : const StudyPlanScreen()),
        GoRoute(
            path: '/session',
            name: 'quizSession',
            builder: (context, state) {
              captured =
                  (state.extra as Map<String, dynamic>)['generationParams']
                      as QuizGenerationParams;
              return Scaffold(
                  body: TextButton(
                      onPressed: () {
                        returned = true;
                        context.pop();
                      },
                      child: const Text('Quiz iniciado')));
            }),
        GoRoute(
            path: '/config',
            name: 'quizConfig',
            builder: (_, __) => const Text('Configuracao indevida')),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        activePlanProvider.overrideWith((ref) async => returned
            ? plan.copyWith(items: [
                first,
                selected.copyWith(status: StudySessionStatus.completed)
              ])
            : plan),
        allPlansProvider.overrideWith((ref) async => [plan]),
        studyPlanRepositoryProvider.overrideWithValue(repository),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      if (!daily) expect(find.text('Próxima sessão: Sintaxe'), findsOneWidget);
      final button = find.text(daily ? 'Fazer Quiz' : 'Estudar isso').last;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Quiz iniciado'), findsOneWidget);
      expect(captured!.studySessionId, 'chosen');
      expect(captured!.topic, contains('Direitos fundamentais'));
      expect(captured!.topic, contains('Organizacao do Estado'));
      expect(find.text('Configuracao indevida'), findsNothing);
      if (!daily) {
        await tester.tap(find.text('Quiz iniciado'));
        await tester.pumpAndSettle();
        expect(find.text('1/2 itens concluídos'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final retry in [false, true]) {
    testWidgets('quiz do plano gera sem voltar ou pedir materia (retry $retry)',
        (tester) async {
      final repository = _QuizRepository();
      final pending = Completer<List<Question>>();
      var calls = 0;
      when(() => repository.generate(
          topic: any(named: 'topic'),
          difficulty: any(named: 'difficulty'),
          quantity: any(named: 'quantity'),
          aiProvider: any(named: 'aiProvider'),
          conteudo: any(named: 'conteudo'),
          documentName: any(named: 'documentName'),
          documentId: any(named: 'documentId'))).thenAnswer((_) {
        calls++;
        return pending.future;
      });
      final router = GoRouter(initialLocation: '/quiz/session', routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('Home indevida')),
        GoRoute(
            path: '/quiz',
            builder: (_, __) => const Text('Configuracao indevida'),
            routes: [
              GoRoute(
                  path: 'session',
                  builder: (_, __) => const QuizSessionScreen(
                      questions: [],
                      generationParams: QuizGenerationParams(
                          topic:
                              'Direito: Direitos fundamentais; Organizacao do Estado',
                          difficulty: 'intermediario',
                          aiProvider: 'groq'))),
            ]),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        quizRepositoryProvider.overrideWithValue(repository),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(router.routeInformationProvider.value.uri.path, '/quiz/session');
      expect(calls, 1);
      expect(find.text('Home indevida'), findsNothing);
      expect(find.text('Configuracao indevida'), findsNothing);
      if (retry) {
        pending.completeError(StateError('provider unavailable'));
        await tester.pump();
        await tester.pump();
        expect(find.text('Tentar novamente'), findsOneWidget);
        when(() =>
            repository.generate(
                topic: any(named: 'topic'),
                difficulty: any(named: 'difficulty'),
                quantity: any(named: 'quantity'),
                aiProvider: any(named: 'aiProvider'),
                conteudo: any(named: 'conteudo'),
                documentName: any(named: 'documentName'),
                documentId: any(named: 'documentId'))).thenAnswer((_) async => [
              Question.fromJson({
                'id': 'q1',
                'text': 'Questao do plano',
                'options': [
                  {'id': 'a', 'text': 'Correta'},
                  {'id': 'b', 'text': 'Errada'}
                ],
                'correct_answer': 'A'
              })
            ]);
        await tester.tap(find.text('Tentar novamente'));
      } else {
        pending.complete([
          Question.fromJson({
            'id': 'q1',
            'text': 'Questao do plano',
            'options': [
              {'id': 'a', 'text': 'Correta'},
              {'id': 'b', 'text': 'Errada'}
            ],
            'correct_answer': 'A'
          })
        ]);
      }
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Questao do plano'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final fromPlan in [false, true]) {
    testWidgets(
        'conclusao registra somente a sessao vinculada (plano $fromPlan)',
        (tester) async {
      final repository = _Plans();
      when(() => repository.updateSessionResult(
          planId: 'chosen-plan',
          sessionId: 'chosen',
          status: StudySessionStatus.completed,
          correctAnswers: any(named: 'correctAnswers'),
          incorrectAnswers: any(named: 'incorrectAnswers'),
          timeSpentMinutes: any(named: 'timeSpentMinutes'),
          score: any(named: 'score'))).thenAnswer((_) async => plan);
      final question = Question.fromJson({
        'id': 'q1',
        'text': 'Questao selecionada',
        'options': [
          {'id': 'a', 'text': 'Correta'},
          {'id': 'b', 'text': 'Errada'}
        ],
        'correct_answer': 'A'
      });
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => QuizSessionScreen(
                questions: [question],
                generationParams:
                    fromPlan ? studyPlanQuizRequest(plan, selected) : null)),
        GoRoute(
            path: '/result',
            name: 'quizResult',
            builder: (_, __) => const Text('Resultado recebido')),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        studyPlanRepositoryProvider.overrideWithValue(repository),
        activePlanProvider.overrideWith(
            (ref) async => plan.copyWith(id: 'another-active-plan')),
        allPlansProvider.overrideWith((ref) async => [plan]),
      ], child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correta'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Ver resultado'));
      await tester.tap(find.text('Ver resultado'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resultado recebido'), findsOneWidget);
      if (fromPlan) {
        expect(
            await QuizRecoveryStore().load('plan:chosen-plan/session:chosen'),
            isNull);
      }
      Future<StudyPlan> verifyCall() => repository.updateSessionResult(
          planId: 'chosen-plan',
          sessionId: 'chosen',
          status: StudySessionStatus.completed,
          correctAnswers: 1,
          incorrectAnswers: 0,
          timeSpentMinutes: 1,
          score: 100);
      if (fromPlan) {
        verify(verifyCall).called(1);
      } else {
        verifyNever(verifyCall);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
