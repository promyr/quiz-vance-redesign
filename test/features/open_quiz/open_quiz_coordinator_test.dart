import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/open_quiz/application/open_quiz_coordinator.dart';
import 'package:quiz_vance_flutter/features/open_quiz/data/open_quiz_repository.dart';
import 'package:quiz_vance_flutter/features/open_quiz/domain/open_quiz_model.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';

class _MockOpenQuizRepository extends Mock implements OpenQuizRepository {}

class _MockAiGenerationGuard extends Mock implements AiGenerationGuard {}

void main() {
  late _MockOpenQuizRepository repository;
  late _MockAiGenerationGuard aiGenerationGuard;
  late OpenQuizCoordinator coordinator;

  final selectedFile = LibraryFile(
    id: 10,
    nome: 'Redacao',
    categoria: 'Enem',
    conteudo: 'Conteudo sobre cidadania',
    criadoEm: DateTime(2026, 3, 29),
  );

  const question = OpenQuestion(
    pergunta: 'Explique cidadania',
    contexto: 'Contexto',
    respostaEsperada: 'Resposta',
  );

  const grade = OpenGrade(
    nota: 88,
    correto: true,
    feedback: 'Bom trabalho',
    pontosForts: ['Clareza'],
    pontosMelhorar: ['Sintese'],
    criterios: {'clareza': 88},
  );

  setUpAll(() {
    registerFallbackValue(question);
  });

  setUp(() {
    repository = _MockOpenQuizRepository();
    aiGenerationGuard = _MockAiGenerationGuard();
    coordinator = OpenQuizCoordinator(
      repository,
      aiGenerationGuard: aiGenerationGuard,
    );
  });

  test('valida tema manual obrigatorio', () async {
    await expectLater(
      coordinator.generateQuestion(
        useLibrary: false,
        tema: '   ',
        difficulty: 'facil',
      ),
      throwsA(isA<OpenQuizValidationException>()),
    );
  });

  test('gera pergunta a partir do arquivo da biblioteca', () async {
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'gemini');
    when(
      () => repository.generateQuestion(
        tema: any(named: 'tema'),
        dificuldade: any(named: 'dificuldade'),
        conteudo: any(named: 'conteudo'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => question);

    final result = await coordinator.generateQuestion(
      useLibrary: true,
      tema: '',
      difficulty: 'intermediario',
      selectedLibraryFile: selectedFile,
    );

    expect(result, same(question));
    verify(
      () => repository.generateQuestion(
        tema: 'Redacao',
        dificuldade: 'intermediario',
        conteudo: any(named: 'conteudo'),
        aiProvider: 'gemini',
      ),
    ).called(1);
  });

  test('valida resposta obrigatoria e delega correcao', () async {
    expect(
      () => coordinator.gradeAnswer(question: question, answer: '   '),
      throwsA(isA<OpenQuizValidationException>()),
    );

    when(
      () => repository.gradeAnswer(
        question: any(named: 'question'),
        answer: any(named: 'answer'),
      ),
    ).thenAnswer((_) async => grade);

    final result = await coordinator.gradeAnswer(
      question: question,
      answer: ' Minha resposta ',
    );

    expect(result, same(grade));
    verify(
      () => repository.gradeAnswer(
        question: question,
        answer: 'Minha resposta',
      ),
    ).called(1);
  });
}
