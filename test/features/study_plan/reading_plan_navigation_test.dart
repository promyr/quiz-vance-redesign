import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/features/study_plan/presentation/today_plan_screen.dart';

class Repository extends Mock implements StudyPlanRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('sessão recomendada de leitura não inicia quiz', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = Repository();
    when(() => repository.listDocuments(purpose: any(named: 'purpose')))
        .thenAnswer((_) async => []);
    final item = StudyPlanItem(
        sessionId: 'reading',
        dia: 'Hoje',
        scheduledDate: DateTime.now().toIso8601String().substring(0, 10),
        subject: 'Matemática',
        tema: 'Frações',
        atividade: 'Ler material',
        duracaoMin: 30,
        prioridade: 1,
        recommendedMode: StudyRecommendedMode.reading);
    final plan = StudyPlan(
        id: 'p',
        title: 'Plano leitura',
        objetivo: 'Concurso',
        tempoDiario: 30,
        items: [item]);
    var openedQuiz = false;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const TodayPlanScreen()),
      GoRoute(
          path: '/quiz-session',
          name: 'quizSession',
          builder: (_, __) {
            openedQuiz = true;
            return const Scaffold(body: Text('Quiz indevido'));
          })
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      activePlanProvider.overrideWith((ref) async => plan),
      allPlansProvider.overrideWith((ref) async => [plan]),
      studyPlanRepositoryProvider.overrideWithValue(repository)
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    final button = find.text('Iniciar sessão recomendada');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(openedQuiz, isFalse,
        reason:
            'Modo READING deve abrir leitura ou informar ausência de documento, sem transformar a sessão em quiz.');
  });
}
