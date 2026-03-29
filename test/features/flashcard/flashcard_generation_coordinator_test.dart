import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/flashcard/application/flashcard_generation_coordinator.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

class _MockAiGenerationGuard extends Mock implements AiGenerationGuard {}

void main() {
  late _MockLibraryRepository libraryRepository;
  late _MockAiGenerationGuard aiGenerationGuard;
  late List<Map<String, dynamic>> storedCards;
  late FlashcardGenerationCoordinator coordinator;

  final selectedFile = LibraryFile(
    id: 10,
    nome: 'Biologia',
    categoria: 'Vestibular',
    conteudo: 'Resumo sobre celulas',
    criadoEm: DateTime(2026, 3, 29),
  );

  final package = StudyPackage(
    titulo: 'Biologia',
    resumoCurto: 'Resumo',
    topicosPrincipais: const ['Celulas'],
    flashcards: const [
      {'front': 'O que e celula?', 'back': 'Unidade basica da vida.'},
      {'front': 'O que e membrana?', 'back': 'Estrutura de delimitacao.'},
    ],
    questoes: const [],
    checklistEstudo: const ['Revisar'],
  );

  setUpAll(() {
    registerFallbackValue(
      LibraryFile(
        id: 0,
        nome: 'Fallback',
        categoria: 'Teste',
        conteudo: 'Conteudo',
        criadoEm: DateTime(2026, 3, 29),
      ),
    );
  });

  setUp(() {
    libraryRepository = _MockLibraryRepository();
    aiGenerationGuard = _MockAiGenerationGuard();
    storedCards = <Map<String, dynamic>>[];
    coordinator = FlashcardGenerationCoordinator(
      aiGenerationGuard: aiGenerationGuard,
      libraryRepository: libraryRepository,
      upsertFlashcard: (card) async {
        storedCards.add(Map<String, dynamic>.from(card));
        return storedCards.length;
      },
    );
  });

  test('valida topico manual obrigatorio', () async {
    await expectLater(
      coordinator.generateAndStore(
        useLibrary: false,
        topic: '   ',
      ),
      throwsA(isA<FlashcardGenerationValidationException>()),
    );
  });

  test('valida selecao obrigatoria de arquivo da biblioteca', () async {
    await expectLater(
      coordinator.generateAndStore(
        useLibrary: true,
        topic: '',
      ),
      throwsA(isA<FlashcardGenerationValidationException>()),
    );
  });

  test('gera e persiste flashcards a partir de topico manual', () async {
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'gemini');
    when(
      () => libraryRepository.generatePackage(
        file: any(named: 'file'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => package);

    final result = await coordinator.generateAndStore(
      useLibrary: false,
      topic: 'Biologia Celular',
    );

    expect(result.createdCount, equals(2));
    expect(result.packageTitle, equals('Biologia'));
    expect(storedCards, hasLength(2));
    expect(storedCards.first['topic'], equals('Biologia'));

    final captured = verify(
      () => libraryRepository.generatePackage(
        file: captureAny(named: 'file'),
        aiProvider: 'gemini',
      ),
    ).captured.single as LibraryFile;

    expect(captured.nome, equals('Biologia Celular'));
    expect(captured.categoria, equals('Gerado por IA'));
  });

  test('gera e persiste flashcards a partir de arquivo selecionado', () async {
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'openai');
    when(
      () => libraryRepository.generatePackage(
        file: any(named: 'file'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => package);

    await coordinator.generateAndStore(
      useLibrary: true,
      topic: '',
      selectedLibraryFile: selectedFile,
    );

    verify(
      () => libraryRepository.generatePackage(
        file: selectedFile,
        aiProvider: 'openai',
      ),
    ).called(1);
    expect(storedCards, hasLength(2));
  });
}
