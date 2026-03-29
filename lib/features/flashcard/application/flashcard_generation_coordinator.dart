import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage.dart';
import '../../library/data/library_repository.dart';
import '../../library/domain/library_model.dart';
import '../../settings/data/ai_generation_guard.dart';

typedef UpsertFlashcardRecord = Future<int> Function(Map<String, dynamic> card);

class FlashcardGenerationValidationException implements Exception {
  const FlashcardGenerationValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FlashcardGenerationResult {
  const FlashcardGenerationResult({
    required this.createdCount,
    required this.packageTitle,
  });

  final int createdCount;
  final String packageTitle;
}

class FlashcardGenerationCoordinator {
  FlashcardGenerationCoordinator({
    required AiGenerationGuard aiGenerationGuard,
    required LibraryRepository libraryRepository,
    required UpsertFlashcardRecord upsertFlashcard,
  })  : _aiGenerationGuard = aiGenerationGuard,
        _libraryRepository = libraryRepository,
        _upsertFlashcard = upsertFlashcard;

  final AiGenerationGuard _aiGenerationGuard;
  final LibraryRepository _libraryRepository;
  final UpsertFlashcardRecord _upsertFlashcard;

  Future<FlashcardGenerationResult> generateAndStore({
    required bool useLibrary,
    required String topic,
    LibraryFile? selectedLibraryFile,
  }) async {
    final trimmedTopic = topic.trim();
    final sourceFile = _resolveSourceFile(
      useLibrary: useLibrary,
      topic: trimmedTopic,
      selectedLibraryFile: selectedLibraryFile,
    );

    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    final package = await _libraryRepository.generatePackage(
      file: sourceFile,
      aiProvider: provider,
    );

    if (package.flashcards.isEmpty) {
      throw Exception(
        useLibrary
            ? 'A IA nao retornou flashcards aderentes ao material selecionado. Tente outro arquivo ou um recorte menor.'
            : 'A IA nao retornou flashcards aderentes ao topico informado. Detalhe mais o tema e tente novamente.',
      );
    }

    final now = DateTime.now();
    final dueDate = now.toIso8601String().substring(0, 10);
    final createdAt = now.toIso8601String();

    for (final card in package.flashcards) {
      await _upsertFlashcard({
        'remote_id': null,
        'front': card['front'] ?? '',
        'back': card['back'] ?? '',
        'topic': package.titulo,
        'interval_days': 1,
        'easiness': 2.5,
        'due_date': dueDate,
        'repetitions': 0,
        'last_reviewed': null,
        'synced': 0,
        'created_at': createdAt,
      });
    }

    return FlashcardGenerationResult(
      createdCount: package.flashcards.length,
      packageTitle: package.titulo,
    );
  }

  LibraryFile _resolveSourceFile({
    required bool useLibrary,
    required String topic,
    required LibraryFile? selectedLibraryFile,
  }) {
    if (useLibrary) {
      if (selectedLibraryFile == null) {
        throw const FlashcardGenerationValidationException(
          'Selecione um material da biblioteca',
        );
      }
      return selectedLibraryFile;
    }

    if (topic.isEmpty) {
      throw const FlashcardGenerationValidationException(
        'Informe um topico',
      );
    }

    return LibraryFile(
      id: 0,
      nome: topic,
      categoria: 'Gerado por IA',
      conteudo: 'Topico: $topic',
      criadoEm: DateTime.now(),
    );
  }
}

final flashcardGenerationCoordinatorProvider =
    Provider<FlashcardGenerationCoordinator>(
  (ref) => FlashcardGenerationCoordinator(
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
    libraryRepository: ref.watch(libraryRepositoryProvider),
    upsertFlashcard: LocalFlashcardWriteGateway.instance.upsertFlashcard,
  ),
);

class LocalFlashcardWriteGateway {
  LocalFlashcardWriteGateway._();

  static final instance = LocalFlashcardWriteGateway._();

  Future<int> upsertFlashcard(Map<String, dynamic> card) {
    return LocalStorage.instance.upsertFlashcard(card);
  }
}
