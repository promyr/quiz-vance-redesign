import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/features/library/application/library_actions_coordinator.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_guard.dart';

class _MockLibraryRepository extends Mock implements LibraryRepository {}

class _MockAiGenerationGuard extends Mock implements AiGenerationGuard {}

void main() {
  late _MockLibraryRepository libraryRepository;
  late _MockAiGenerationGuard aiGenerationGuard;
  late LibraryActionsCoordinator coordinator;

  final file = LibraryFile(
    id: 1,
    nome: 'Biologia',
    categoria: 'Vestibular',
    conteudo: 'Resumo sobre celulas',
    criadoEm: DateTime(2026, 3, 29),
  );

  final package = StudyPackage(
    titulo: 'Biologia',
    resumoCurto: 'Resumo',
    topicosPrincipais: const ['Celulas'],
    flashcards: const [],
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
    coordinator = LibraryActionsCoordinator(
      libraryRepository,
      aiGenerationGuard: aiGenerationGuard,
    );
  });

  test('delegates addFile para o repositorio', () async {
    when(
      () => libraryRepository.addFile(
        nome: any(named: 'nome'),
        conteudo: any(named: 'conteudo'),
        categoria: any(named: 'categoria'),
      ),
    ).thenAnswer((_) async => file);

    final created = await coordinator.addFile(
      nome: 'Biologia',
      conteudo: 'Resumo sobre celulas',
      categoria: 'Vestibular',
    );

    expect(created.id, equals(1));
    verify(
      () => libraryRepository.addFile(
        nome: 'Biologia',
        conteudo: 'Resumo sobre celulas',
        categoria: 'Vestibular',
      ),
    ).called(1);
  });

  test('delegates deleteFile para o repositorio', () async {
    when(() => libraryRepository.deleteFile(1)).thenAnswer((_) async {});

    await coordinator.deleteFile(1);

    verify(() => libraryRepository.deleteFile(1)).called(1);
  });

  test('generatePackage resolve provider e encaminha para o repositorio',
      () async {
    when(() => aiGenerationGuard.ensureReadyForGeneration())
        .thenAnswer((_) async => 'gemini');
    when(
      () => libraryRepository.generatePackage(
        file: any(named: 'file'),
        aiProvider: any(named: 'aiProvider'),
      ),
    ).thenAnswer((_) async => package);

    final generated = await coordinator.generatePackage(file);

    expect(generated.titulo, equals('Biologia'));
    verify(() => aiGenerationGuard.ensureReadyForGeneration()).called(1);
    verify(
      () => libraryRepository.generatePackage(
        file: file,
        aiProvider: 'gemini',
      ),
    ).called(1);
  });
}
