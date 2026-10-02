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

  test('mantem provider no servidor e reduz contexto ao repetir', () async {
    when(
      () => aiGenerationGuard.ensureReadyForGeneration(
        overrideProvider: any(named: 'overrideProvider'),
      ),
    ).thenAnswer((invocation) async {
      return invocation.namedArguments[#overrideProvider] as String? ??
          'gemini';
    });
    var attempts = 0;
    when(
      () => repository.generate(
        topic: any(named: 'topic'),
        difficulty: any(named: 'difficulty'),
        quantity: any(named: 'quantity'),
        aiProvider: any(named: 'aiProvider'),
        conteudo: any(named: 'conteudo'),
        documentName: any(named: 'documentName'),
        documentId: any(named: 'documentId'),
      ),
    ).thenAnswer((invocation) async {
      attempts++;
      if (attempts == 1) {
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
    expect(result.aiProvider, equals('gemini'));
    expect(result.infiniteMode, isTrue);
    verify(
      () => repository.generate(
        topic: selectedFile.nome,
        difficulty: 'hard',
        quantity: 5,
        aiProvider: 'gemini',
        conteudo: any(named: 'conteudo'),
        documentName: any(named: 'documentName'),
        documentId: any(named: 'documentId'),
      ),
    ).called(2);
  });

  test('nao repete outro provider no cliente quando gateway esgota o pool',
      () async {
    when(
      () => aiGenerationGuard.ensureReadyForGeneration(
        overrideProvider: any(named: 'overrideProvider'),
      ),
    ).thenAnswer((invocation) async {
      return invocation.namedArguments[#overrideProvider] as String? ??
          'gemini';
    });
    when(
      () => repository.generate(
        topic: any(named: 'topic'),
        difficulty: any(named: 'difficulty'),
        quantity: any(named: 'quantity'),
        aiProvider: any(named: 'aiProvider'),
        conteudo: any(named: 'conteudo'),
        documentName: any(named: 'documentName'),
        documentId: any(named: 'documentId'),
      ),
    ).thenAnswer((invocation) async {
      throw const RemoteServiceException('Quota exceeded');
    });

    await expectLater(
      coordinator.generate(
        useLibrary: false,
        topic: 'Direito constitucional',
        difficulty: 'medium',
        quantity: 10,
        infiniteMode: false,
        preferredProvider: 'gemini',
      ),
      throwsA(isA<RemoteServiceException>()),
    );

    verify(
      () => repository.generate(
        topic: 'Direito constitucional',
        difficulty: 'medium',
        quantity: 10,
        aiProvider: 'gemini',
        conteudo: null,
        documentName: null,
        documentId: null,
      ),
    ).called(1);
    verifyNever(
      () => repository.generate(
        topic: any(named: 'topic'),
        difficulty: any(named: 'difficulty'),
        quantity: any(named: 'quantity'),
        aiProvider: 'groq',
        conteudo: any(named: 'conteudo'),
        documentName: any(named: 'documentName'),
        documentId: any(named: 'documentId'),
      ),
    );
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

  group('sliceStudyMaterialForSession', () {
    test('retorna material original se for menor ou igual a windowChars', () {
      const shortText = 'Texto pequeno de estudo.';
      final result = sliceStudyMaterialForSession(shortText, windowChars: 100);
      expect(result, equals(shortText));
    });

    test('fatia trechos distintos para sementes temporais diferentes em material longo', () {
      final longText = List.generate(100, (i) => 'Paragrafo $i: conteudo detalhado de estudo sobre tema $i. ').join();
      expect(longText.length, greaterThan(5000));

      final slice0 = sliceStudyMaterialForSession(
        longText,
        seed: 0,
        windowChars: 2000,
        overlapChars: 400,
      );
      final slice1 = sliceStudyMaterialForSession(
        longText,
        seed: 1,
        windowChars: 2000,
        overlapChars: 400,
      );

      expect(slice0.length, lessThanOrEqualTo(2000));
      expect(slice1.length, lessThanOrEqualTo(2000));
      expect(slice0, isNot(equals(slice1)));
      expect(slice0.startsWith('Paragrafo 0:'), isTrue);
      expect(slice1.startsWith('Paragrafo 0:'), isFalse);
    });
  });
}
