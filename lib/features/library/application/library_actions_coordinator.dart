import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/ai_generation_guard.dart';
import '../data/library_repository.dart';
import '../domain/library_model.dart';

class LibraryActionsCoordinator {
  const LibraryActionsCoordinator(
    this._libraryRepository, {
    required AiGenerationGuard aiGenerationGuard,
  }) : _aiGenerationGuard = aiGenerationGuard;

  final LibraryRepository _libraryRepository;
  final AiGenerationGuard _aiGenerationGuard;

  Future<LibraryFile> addFile({
    required String nome,
    required String conteudo,
    String? categoria,
  }) {
    return _libraryRepository.addFile(
      nome: nome,
      conteudo: conteudo,
      categoria: categoria,
    );
  }

  Future<void> deleteFile(int id) {
    return _libraryRepository.deleteFile(id);
  }

  Future<StudyPackage> generatePackage(LibraryFile file) async {
    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    return _libraryRepository.generatePackage(
      file: file,
      aiProvider: provider,
    );
  }
}

final libraryActionsCoordinatorProvider = Provider<LibraryActionsCoordinator>(
  (ref) => LibraryActionsCoordinator(
    ref.watch(libraryRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
  ),
);
