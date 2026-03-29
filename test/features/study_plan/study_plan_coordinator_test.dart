import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';
import 'package:quiz_vance_flutter/features/study_plan/application/study_plan_coordinator.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';

class _MockStudyPlanRepository extends Mock implements StudyPlanRepository {}

class _MockAiGenerationGuard extends Mock implements AiGenerationGuard {}

void main() {
  late _MockStudyPlanRepository repository;
  late _MockAiGenerationGuard aiGenerationGuard;
  late StudyPlanCoordinator coordinator;

  final plan = StudyPlan(
    objetivo: 'Aprovar no concurso',
    dataProva: '01/12/2026',
    tempoDiario: 60,
    items: [
      const StudyPlanItem(
        id: 1,
        dia: 'Segunda',
        tema: 'Direito',
        atividade: 'Revisar',
        duracaoMin: 60,
        prioridade: 1,
      ),
    ],
  );

  setUp(() {
    repository = _MockStudyPlanRepository();
    aiGenerationGuard = _MockAiGenerationGuard();
    coordinator = StudyPlanCoordinator(
      repository,
      aiGenerationGuard: aiGenerationGuard,
    );
  });

  test('valida objetivo obrigatorio', () async {
    await expectLater(
      coordinator.generatePlan(
        objective: '   ',
        examDate: null,
        tempoDiario: 30,
        rawTopics: '',
      ),
      throwsA(isA<StudyPlanValidationException>()),
    );
  });

  test('gera plano com topicos normalizados', () async {
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'gemini');
    when(
      () => repository.generatePlan(
        objetivo: any(named: 'objetivo'),
        dataProva: any(named: 'dataProva'),
        tempoDiario: any(named: 'tempoDiario'),
        topicos: any(named: 'topicos'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => plan);

    final result = await coordinator.generatePlan(
      objective: ' Aprovar no concurso ',
      examDate: ' 01/12/2026 ',
      tempoDiario: 60,
      rawTopics: 'Direito Constitucional, Raciocinio Logico,  ',
    );

    expect(result, same(plan));
    verify(
      () => repository.generatePlan(
        objetivo: 'Aprovar no concurso',
        dataProva: '01/12/2026',
        tempoDiario: 60,
        topicos: ['Direito Constitucional', 'Raciocinio Logico'],
        aiProvider: 'gemini',
      ),
    ).called(1);
  });
}
