import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/features/study_plan/presentation/study_plan_screen.dart';

class _Plans extends Mock implements StudyPlanRepository {}

void main() {
  testWidgets(
      'plano aberto atualiza progresso quando sessão conclui em outra tela',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final item = StudyPlanItem(
        sessionId: 's',
        dia: 'Hoje',
        subject: 'Matemática',
        tema: 'Porcentagens',
        atividade: 'Quiz',
        duracaoMin: 30,
        prioridade: 1);
    final plan = StudyPlan(
        id: 'p',
        title: 'Concurso',
        objetivo: 'Concurso',
        tempoDiario: 30,
        items: [item]);
    final state = StateProvider<StudyPlan>((ref) => plan);
    final repository = _Plans();
    when(() => repository.listDocuments(purpose: any(named: 'purpose')))
        .thenAnswer((_) async => []);
    final container = ProviderContainer(overrides: [
      activePlanProvider.overrideWith((ref) async => ref.watch(state)),
      studyPlanRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: StudyPlanScreen())));
    await tester.pumpAndSettle();
    expect(find.text('0/1 itens concluídos'), findsOneWidget);
    container.read(state.notifier).state = plan
        .copyWith(items: [item.copyWith(status: StudySessionStatus.completed)]);
    await tester.pumpAndSettle();
    expect(find.text('1/1 itens concluídos'), findsOneWidget);
  });
}
