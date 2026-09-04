import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../settings/data/ai_generation_fallback.dart';
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

    try {
      return await _libraryRepository.generatePackage(
        file: file,
        aiProvider: provider,
      );
    } catch (firstError) {
      if (!isRetryableAiGenerationFailure(firstError)) {
        rethrow;
      }

      final config = await _aiGenerationGuard.loadConfig(
        overrideProvider: provider,
      );
      final providerCandidates = buildAiProviderFallbackOrder(
        preferredProvider: provider,
        config: config,
      );

      Object lastError = firstError;

      for (final candidateProvider in providerCandidates) {
        if (candidateProvider == provider) continue;

        try {
          await _aiGenerationGuard.ensureReadyForGeneration(
            overrideProvider: candidateProvider,
          );
          return await _libraryRepository.generatePackage(
            file: file,
            aiProvider: candidateProvider,
          );
        } catch (retryError) {
          lastError = retryError;
          if (!isRetryableAiGenerationFailure(retryError)) {
            rethrow;
          }
        }
      }

      final message = userVisibleErrorMessage(
        lastError,
        fallback: 'Nao foi possivel gerar o pacote de estudos agora.',
      );
      throw Exception(message);
    }
  }
}

final libraryActionsCoordinatorProvider = Provider<LibraryActionsCoordinator>(
  (ref) => LibraryActionsCoordinator(
    ref.watch(libraryRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
  ),
);
