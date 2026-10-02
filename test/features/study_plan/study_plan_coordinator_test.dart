import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';
import 'package:quiz_vance_flutter/features/study_plan/application/study_plan_coordinator.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_model.dart';
import 'package:quiz_vance_flutter/features/study_plan/domain/study_plan_notice_analysis.dart';

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

  test('analisa edital usando cargo, texto extraido e provedor ativo',
      () async {
    const analysis = StudyPlanNoticeAnalysis(
      jobTitle: 'Analista',
      subjects: [
        StudyPlanNoticeSubject(
          name: 'Português',
          topics: ['Interpretação de texto'],
          evidence: 'Língua Portuguesa: interpretação de textos.',
          peso: null,
          numQuestoes: null,
        ),
      ],
      concursoInfo: null,
      cronograma: null,
      cargosPopup: [],
    );
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'gemini');
    when(
      () => repository.analyzeNotice(
        jobTitle: any(named: 'jobTitle'),
        selectedCargo: any(named: 'selectedCargo'),
        noticeText: any(named: 'noticeText'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => analysis);

    final result = await coordinator.analyzeNotice(
      jobTitle: ' Analista ',
      noticeText: ' texto extraído do PDF ',
    );

    expect(result, same(analysis));
    verify(
      () => repository.analyzeNotice(
        jobTitle: 'Analista',
        selectedCargo: null,
        noticeText: 'texto extraído do PDF',
        aiProvider: 'gemini',
      ),
    ).called(1);
  });

  test('mantem topicos revisados sem separar virgulas internas', () async {
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

    await coordinator.generatePlan(
      objective: 'Analista',
      tempoDiario: 60,
      rawTopics: '',
      reviewedTopics: ['Português: sintaxe, semântica'],
    );

    verify(
      () => repository.generatePlan(
        objetivo: 'Analista',
        dataProva: null,
        tempoDiario: 60,
        topicos: ['Português: sintaxe, semântica'],
        aiProvider: 'gemini',
      ),
    ).called(1);
  });
}
