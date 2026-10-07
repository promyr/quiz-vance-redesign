import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/shared/widgets/active_plan_card.dart';

void main() {
  test('sessao datada concluida nao reaparece em outra semana', () {
    final plan = StudyPlan(
      objetivo: 'Concurso',
      tempoDiario: 30,
      items: [
        StudyPlanItem(
          dia: 'Segunda',
          scheduledDate: '2026-09-28',
          tema: 'Direito',
          atividade: 'Quiz',
          duracaoMin: 30,
          prioridade: 1,
          concluido: true,
        ),
      ],
    );
    expect(plan.getSessionsForDate(DateTime(2026, 9, 28)), hasLength(1));
    expect(plan.getSessionsForDate(DateTime(2026, 10, 5)), isEmpty);
  });

  testWidgets('criacao de plano fica apenas na Biblioteca', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [activePlanProvider.overrideWith((ref) async => null)],
      child: const MaterialApp(home: Scaffold(body: ActivePlanCard())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Criar plano de estudos'), findsNothing);
  });

  testWidgets('revisao nao comprime titulo em tela estreita com fonte grande',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final plan = StudyPlan(
        id: 'empty',
        title: 'Plano importado',
        objetivo: 'Concurso',
        tempoDiario: 30,
        items: const []);
    await tester.pumpWidget(ProviderScope(
      overrides: [activePlanProvider.overrideWith((ref) async => plan)],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.6)),
              child: child!),
          home: const Scaffold(body: ActivePlanCard())),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester.getSize(find.text('Plano sem sessões')).width, greaterThan(180));
  });

  testWidgets('plano ativo vazio nao derruba a Home', (tester) async {
    final emptyPlan = StudyPlan(
      id: 'empty-plan',
      title: 'Plano importado',
      objetivo: 'Concurso',
      tempoDiario: 30,
      items: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePlanProvider.overrideWith((ref) async => emptyPlan),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ActivePlanCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Plano sem sessões'), findsOneWidget);
  });

  for (final completed in [false, true]) {
    testWidgets('plano com sessoes em 320px fonte 1.6 concluido $completed',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final plan = StudyPlan(
          id: 'plan',
          title: 'Plano de estudo do concurso',
          objetivo: 'Concurso',
          tempoDiario: 30,
          items: [
            StudyPlanItem(
              dia: '1',
              scheduledDate: DateTime.now().toIso8601String().substring(0, 10),
              subject: 'Direito Constitucional',
              tema: 'Direitos fundamentais',
              atividade: 'QUIZ',
              duracaoMin: 30,
              prioridade: 1,
              concluido: completed,
              status: completed
                  ? StudySessionStatus.completed
                  : StudySessionStatus.pending,
            )
          ]);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            activePlanProvider.overrideWith((ref) async => plan),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.6)),
                  child: child!),
              home: const Scaffold(
                  body: SingleChildScrollView(child: ActivePlanCard())))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(completed ? 'Ver Plano' : 'Continuar'), findsOneWidget);
    });
  }
}
