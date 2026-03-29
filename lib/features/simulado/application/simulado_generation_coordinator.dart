import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/content/study_material_sanitizer.dart';
import '../../library/domain/library_model.dart';
import '../../quiz/domain/question_model.dart';
import '../../settings/data/ai_generation_guard.dart';
import '../data/simulado_repository.dart';

class SimuladoGenerationValidationException implements Exception {
  const SimuladoGenerationValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SimuladoGenerationResult {
  const SimuladoGenerationResult({
    required this.questions,
    required this.durationSeconds,
  });

  final List<Question> questions;
  final int durationSeconds;
}

class SimuladoGenerationCoordinator {
  const SimuladoGenerationCoordinator(
    this._simuladoRepository, {
    required AiGenerationGuard aiGenerationGuard,
  }) : _aiGenerationGuard = aiGenerationGuard;

  final SimuladoRepository _simuladoRepository;
  final AiGenerationGuard _aiGenerationGuard;

  Future<SimuladoGenerationResult> generateExam({
    required bool useLibrary,
    required String topic,
    required String difficulty,
    required int quantity,
    required int durationMinutes,
    LibraryFile? selectedLibraryFile,
  }) async {
    final selection = _resolveSelection(
      useLibrary: useLibrary,
      topic: topic,
      selectedLibraryFile: selectedLibraryFile,
    );
    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    final questions = await _simuladoRepository.generateExam(
      quantity: quantity,
      difficulty: difficulty,
      topic: selection.topic,
      conteudo: selection.libraryContent,
      aiProvider: provider,
    );

    return SimuladoGenerationResult(
      questions: questions,
      durationSeconds: durationMinutes * 60,
    );
  }

  _SimuladoSelection _resolveSelection({
    required bool useLibrary,
    required String topic,
    LibraryFile? selectedLibraryFile,
  }) {
    if (useLibrary) {
      if (selectedLibraryFile == null) {
        throw const SimuladoGenerationValidationException(
          'Selecione um material da biblioteca.',
        );
      }

      return _SimuladoSelection(
        topic: selectedLibraryFile.nome,
        libraryContent: sanitizeStudyMaterialForPrompt(
          selectedLibraryFile.conteudo,
          maxChars: 2600,
        ),
      );
    }

    final trimmedTopic = topic.trim();
    return _SimuladoSelection(
      topic: trimmedTopic.isEmpty ? null : trimmedTopic,
      libraryContent: null,
    );
  }
}

class _SimuladoSelection {
  const _SimuladoSelection({
    required this.topic,
    required this.libraryContent,
  });

  final String? topic;
  final String? libraryContent;
}

final simuladoGenerationCoordinatorProvider =
    Provider<SimuladoGenerationCoordinator>(
  (ref) => SimuladoGenerationCoordinator(
    ref.watch(simuladoRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
  ),
);
