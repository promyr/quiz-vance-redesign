import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';
import 'package:quiz_vance_flutter/features/simulado/application/simulado_generation_coordinator.dart';
import 'package:quiz_vance_flutter/features/simulado/data/simulado_repository.dart';

class _MockSimuladoRepository extends Mock implements SimuladoRepository {}

class _MockAiGenerationGuard extends Mock implements AiGenerationGuard {}

void main() {
  late _MockSimuladoRepository repository;
  late _MockAiGenerationGuard aiGenerationGuard;
  late SimuladoGenerationCoordinator coordinator;

  final selectedFile = LibraryFile(
    id: 7,
    nome: 'Matematica',
    categoria: 'Enem',
    conteudo: 'Conteudo sobre geometria',
    criadoEm: DateTime(2026, 3, 29),
  );

  const questions = [
    Question(
      id: 'q1',
      text: 'Pergunta 1',
      options: [
        QuizOption(id: 'a', text: 'A'),
        QuizOption(id: 'b', text: 'B'),
      ],
      correctOptionId: 'a',
    ),
  ];

  setUp(() {
    repository = _MockSimuladoRepository();
    aiGenerationGuard = _MockAiGenerationGuard();
    coordinator = SimuladoGenerationCoordinator(
      repository,
      aiGenerationGuard: aiGenerationGuard,
    );
  });

  test('valida selecao de material quando usa biblioteca', () async {
    await expectLater(
      coordinator.generateExam(
        useLibrary: true,
        topic: '',
        difficulty: 'mixed',
        quantity: 20,
        durationMinutes: 60,
      ),
      throwsA(isA<SimuladoGenerationValidationException>()),
    );
  });

  test('gera simulado e retorna duracao em segundos', () async {
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'openai');
    when(
      () => repository.generateExam(
        quantity: any(named: 'quantity'),
        difficulty: any(named: 'difficulty'),
        topic: any(named: 'topic'),
        conteudo: any(named: 'conteudo'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => questions);

    final result = await coordinator.generateExam(
      useLibrary: true,
      topic: '',
      difficulty: 'mixed',
      quantity: 20,
      durationMinutes: 90,
      selectedLibraryFile: selectedFile,
    );

    expect(result.questions, equals(questions));
    expect(result.durationSeconds, equals(5400));
    verify(
      () => repository.generateExam(
        quantity: 20,
        difficulty: 'mixed',
        topic: 'Matematica',
        conteudo: any(named: 'conteudo'),
        aiProvider: 'openai',
      ),
    ).called(1);
  });
}
