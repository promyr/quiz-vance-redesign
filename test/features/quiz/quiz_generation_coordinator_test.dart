import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/observability/app_observability.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/quiz/application/quiz_generation_coordinator.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_repository.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';

class _MockQuizRepository extends Mock implements QuizRepository {}

class _MockAiGenerationGuard extends Mock implements AiGenerationGuard {}

void main() {
  late _MockQuizRepository repository;
  late _MockAiGenerationGuard aiGenerationGuard;
  late QuizGenerationCoordinator coordinator;

  final selectedFile = LibraryFile(
    id: 99,
    nome: 'Historia',
    categoria: 'Vestibular',
    conteudo: 'Conteudo grande sobre revolucao francesa',
    criadoEm: DateTime(2026, 3, 29),
  );

  const questions = [
    Question(
      id: 'q1',
      text: 'Pergunta',
      options: [
        QuizOption(id: 'a', text: 'A'),
        QuizOption(id: 'b', text: 'B'),
      ],
      correctOptionId: 'a',
      difficulty: 'medium',
    ),
  ];

  setUp(() {
    repository = _MockQuizRepository();
    aiGenerationGuard = _MockAiGenerationGuard();
    coordinator = QuizGenerationCoordinator(
      repository,
      aiGenerationGuard: aiGenerationGuard,
      observability: AppObservability(maxEntries: 20),
    );
  });

  test('valida topico manual obrigatorio', () async {
    await expectLater(
      coordinator.generate(
        useLibrary: false,
        topic: '   ',
        difficulty: 'medium',
        quantity: 10,
        infiniteMode: false,
        preferredProvider: 'gemini',
      ),
      throwsA(isA<QuizGenerationValidationException>()),
    );
  });

  test('recupera geracao com fallback de provider e contexto', () async {
    when(
      () => aiGenerationGuard.ensureReadyForGeneration(
        overrideProvider: any(named: 'overrideProvider'),
      ),
    ).thenAnswer((invocation) async {
      return invocation.namedArguments[#overrideProvider] as String? ??
          'gemini';
    });
    when(
      () => aiGenerationGuard.loadConfig(
        overrideProvider: any(named: 'overrideProvider'),
      ),
    ).thenAnswer(
      (_) async => const AiGenerationConfigState(
        selectedProvider: 'gemini',
        selectedProviderLabel: 'Gemini',
        selectedProviderKey: 'g-key',
        geminiKey: 'g-key',
        openaiKey: 'o-key',
        groqKey: '',
        syncPending: false,
        lastSyncedProvider: 'gemini',
      ),
    );
    when(
      () => repository.generate(
        topic: any(named: 'topic'),
        difficulty: any(named: 'difficulty'),
        quantity: any(named: 'quantity'),
        aiProvider: any(named: 'aiProvider'),
        conteudo: any(named: 'conteudo'),
      ),
    ).thenAnswer((invocation) async {
      final aiProvider = invocation.namedArguments[#aiProvider] as String?;
      if (aiProvider == 'gemini') {
        throw const RemoteServiceException('Tente novamente');
      }
      return questions;
    });

    final result = await coordinator.generate(
      useLibrary: true,
      topic: '',
      difficulty: 'hard',
      quantity: 15,
      infiniteMode: true,
      preferredProvider: 'gemini',
      selectedLibraryFile: selectedFile,
    );

    expect(result.questions, equals(questions));
    expect(result.aiProvider, equals('openai'));
    expect(result.infiniteMode, isTrue);
    verify(
      () => repository.generate(
        topic: selectedFile.nome,
        difficulty: 'hard',
        quantity: 5,
        aiProvider: 'gemini',
        conteudo: any(named: 'conteudo'),
      ),
    ).called(1);
    verify(
      () => repository.generate(
        topic: selectedFile.nome,
        difficulty: 'hard',
        quantity: 5,
        aiProvider: 'openai',
        conteudo: any(named: 'conteudo'),
      ),
    ).called(greaterThanOrEqualTo(1));
  });

  test('limpa memoria a partir do topico selecionado', () async {
    when(() => repository.clearSeenQuestions(topic: any(named: 'topic')))
        .thenAnswer((_) async {});

    await coordinator.clearSeenQuestions(
      useLibrary: true,
      topic: '',
      selectedLibraryFile: selectedFile,
    );

    verify(() => repository.clearSeenQuestions(topic: 'Historia')).called(1);
  });
}
