import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/content/study_material_sanitizer.dart';
import '../../library/domain/library_model.dart';
import '../../settings/data/ai_generation_guard.dart';
import '../data/open_quiz_repository.dart';
import '../domain/open_quiz_model.dart';

class OpenQuizValidationException implements Exception {
  const OpenQuizValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpenQuizCoordinator {
  const OpenQuizCoordinator(
    this._openQuizRepository, {
    required AiGenerationGuard aiGenerationGuard,
  }) : _aiGenerationGuard = aiGenerationGuard;

  final OpenQuizRepository _openQuizRepository;
  final AiGenerationGuard _aiGenerationGuard;

  Future<OpenQuestion> generateQuestion({
    required bool useLibrary,
    required String tema,
    required String difficulty,
    LibraryFile? selectedLibraryFile,
  }) async {
    final selection = _resolveSelection(
      useLibrary: useLibrary,
      tema: tema,
      selectedLibraryFile: selectedLibraryFile,
    );
    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    return _openQuizRepository.generateQuestion(
      tema: selection.tema,
      dificuldade: difficulty,
      conteudo: selection.libraryContent,
      aiProvider: provider,
    );
  }

  Future<OpenGrade> gradeAnswer({
    required OpenQuestion question,
    required String answer,
  }) {
    final trimmedAnswer = answer.trim();
    if (trimmedAnswer.isEmpty) {
      throw const OpenQuizValidationException('Escreva uma resposta.');
    }

    return _openQuizRepository.gradeAnswer(
      question: question,
      answer: trimmedAnswer,
    );
  }

  _OpenQuizSelection _resolveSelection({
    required bool useLibrary,
    required String tema,
    LibraryFile? selectedLibraryFile,
  }) {
    if (useLibrary) {
      if (selectedLibraryFile == null) {
        throw const OpenQuizValidationException(
          'Selecione um material da biblioteca.',
        );
      }

      return _OpenQuizSelection(
        tema: selectedLibraryFile.nome,
        libraryContent: sanitizeStudyMaterialForPrompt(
          selectedLibraryFile.conteudo,
          maxChars: 1800,
        ),
      );
    }

    final trimmedTema = tema.trim();
    if (trimmedTema.isEmpty) {
      throw const OpenQuizValidationException('Informe um tema.');
    }

    return _OpenQuizSelection(
      tema: trimmedTema,
      libraryContent: null,
    );
  }
}

class _OpenQuizSelection {
  const _OpenQuizSelection({
    required this.tema,
    required this.libraryContent,
  });

  final String tema;
  final String? libraryContent;
}

final openQuizCoordinatorProvider = Provider<OpenQuizCoordinator>(
  (ref) => OpenQuizCoordinator(
    ref.watch(openQuizRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
  ),
);
