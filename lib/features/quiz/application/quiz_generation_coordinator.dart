import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/content/study_material_sanitizer.dart';
import '../../../core/observability/app_observability.dart';
import '../../library/domain/library_model.dart';
import '../../settings/data/ai_generation_fallback.dart';
import '../../settings/data/ai_generation_guard.dart';
import '../data/quiz_repository.dart';
import '../domain/question_model.dart';

class QuizGenerationValidationException implements Exception {
  const QuizGenerationValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class QuizGenerationResult {
  const QuizGenerationResult({
    required this.questions,
    required this.topic,
    required this.difficulty,
    required this.aiProvider,
    required this.infiniteMode,
    this.context,
  });

  final List<Question> questions;
  final String topic;
  final String difficulty;
  final String aiProvider;
  final String? context;
  final bool infiniteMode;
}

class QuizGenerationCoordinator {
  QuizGenerationCoordinator(
    this._quizRepository, {
    required AiGenerationGuard aiGenerationGuard,
    required AppObservability observability,
  })  : _aiGenerationGuard = aiGenerationGuard,
        _observability = observability;

  final QuizRepository _quizRepository;
  final AiGenerationGuard _aiGenerationGuard;
  final AppObservability _observability;

  Future<QuizGenerationResult> generate({
    required bool useLibrary,
    required String topic,
    required String difficulty,
    required int quantity,
    required bool infiniteMode,
    required String preferredProvider,
    LibraryFile? selectedLibraryFile,
  }) async {
    final selection = _resolveSelection(
      useLibrary: useLibrary,
      topic: topic,
      selectedLibraryFile: selectedLibraryFile,
    );
    _observability.trackEvent(
      'quiz.generate_requested',
      attributes: <String, Object?>{
        'source': selection.useLibrary ? 'library' : 'manual',
        'difficulty': difficulty,
        'infinite_mode': infiniteMode,
      },
    );

    final effectiveQuantity = infiniteMode ? 5 : quantity;
    var resolvedProvider = await _aiGenerationGuard.ensureReadyForGeneration(
      overrideProvider: preferredProvider,
    );
    var resolvedContext = selection.libraryContext;

    try {
      final questions = await _quizRepository.generate(
        topic: selection.topic,
        difficulty: difficulty,
        quantity: effectiveQuantity,
        aiProvider: resolvedProvider,
        conteudo: resolvedContext,
        documentName: selection.documentName,
        documentId: selection.documentId,
      );
      _observability.trackEvent(
        'quiz.generate_succeeded',
        attributes: <String, Object?>{
          'provider': resolvedProvider,
          'question_count': questions.length,
        },
      );

      return QuizGenerationResult(
        questions: questions,
        topic: selection.topic,
        difficulty: difficulty,
        aiProvider: resolvedProvider,
        context: resolvedContext,
        infiniteMode: infiniteMode,
      );
    } catch (firstError) {
      if (!isRetryableAiGenerationFailure(firstError)) {
        rethrow;
      }

      final providerCandidates = <String>[resolvedProvider];
      final contextCandidates = _buildContextFallbackOrder(
        initialContext: selection.libraryContext,
        rawLibraryContent: selection.rawLibraryContent,
      );

      Object lastError = firstError;

      for (final candidateProvider in providerCandidates) {
        for (final candidateContext in contextCandidates) {
          final sameAsOriginal = candidateProvider == resolvedProvider &&
              candidateContext == resolvedContext;
          if (sameAsOriginal) continue;

          try {
            final questions = await _quizRepository.generate(
              topic: selection.topic,
              difficulty: difficulty,
              quantity: effectiveQuantity,
              aiProvider: candidateProvider,
              conteudo: candidateContext,
              documentName: selection.documentName,
              documentId: selection.documentId,
            );

            resolvedProvider = candidateProvider;
            resolvedContext = candidateContext;
            _observability.trackEvent(
              'quiz.generate_recovered_with_fallback',
              level: AppEventLevel.warning,
              attributes: <String, Object?>{
                'provider': candidateProvider,
                'used_library': selection.useLibrary,
              },
            );
            return QuizGenerationResult(
              questions: questions,
              topic: selection.topic,
              difficulty: difficulty,
              aiProvider: resolvedProvider,
              context: resolvedContext,
              infiniteMode: infiniteMode,
            );
          } catch (retryError) {
            lastError = retryError;
            if (!isRetryableAiGenerationFailure(retryError)) {
              rethrow;
            }
          }
        }
      }

      _observability.reportError(
        'quiz.generate_failed',
        lastError,
        StackTrace.current,
      );
      throw lastError;
    }
  }

  Future<void> clearSeenQuestions({
    required bool useLibrary,
    required String topic,
    LibraryFile? selectedLibraryFile,
  }) {
    final trimmedTopic = useLibrary
        ? selectedLibraryFile?.nome.trim()
        : topic.trim().isNotEmpty
            ? topic.trim()
            : null;
    _observability.trackEvent(
      'quiz.clear_memory_requested',
      attributes: <String, Object?>{
        'source': useLibrary ? 'library' : 'manual',
        if (trimmedTopic != null) 'topic': trimmedTopic,
      },
    );
    return _quizRepository.clearSeenQuestions(topic: trimmedTopic);
  }

  _QuizSelection _resolveSelection({
    required bool useLibrary,
    required String topic,
    LibraryFile? selectedLibraryFile,
  }) {
    if (useLibrary) {
      if (selectedLibraryFile == null) {
        throw const QuizGenerationValidationException(
          'Selecione um material da biblioteca.',
        );
      }

      final docId = int.tryParse(selectedLibraryFile.id.toString());
      final slicedContent = sliceStudyMaterialForSession(
        selectedLibraryFile.conteudo,
      );
      return _QuizSelection(
        topic: selectedLibraryFile.nome,
        libraryContext: sanitizeStudyMaterialForPrompt(
          slicedContent,
          maxChars: 2200,
        ),
        rawLibraryContent: slicedContent,
        documentName: selectedLibraryFile.nome,
        documentId: docId,
        useLibrary: true,
      );
    }

    final trimmedTopic = topic.trim();
    if (trimmedTopic.isEmpty) {
      throw const QuizGenerationValidationException('Informe um topico.');
    }

    return _QuizSelection(
      topic: trimmedTopic,
      libraryContext: null,
      rawLibraryContent: null,
      documentName: null,
      documentId: null,
      useLibrary: false,
    );
  }
}

class _QuizSelection {
  const _QuizSelection({
    required this.topic,
    required this.libraryContext,
    required this.rawLibraryContent,
    required this.documentName,
    required this.documentId,
    required this.useLibrary,
  });

  final String topic;
  final String? libraryContext;
  final String? rawLibraryContent;
  final String? documentName;
  final int? documentId;
  final bool useLibrary;
}

/// Retorna uma fatia do material de acordo com uma semente temporal (por padrão a hora UTC atual),
/// garantindo que sessões consecutivas ou em horários diferentes explorem trechos distintos de PDFs longos.
String sliceStudyMaterialForSession(
  String raw, {
  int? seed,
  int windowChars = 3000,
  int overlapChars = 500,
}) {
  if (raw.length <= windowChars) return raw;

  final effectiveSeed =
      seed ?? (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 3600000);
  final strideChars = windowChars - overlapChars;
  final maxPositions = ((raw.length - overlapChars) / strideChars).ceil();
  if (maxPositions <= 1) {
    return raw.substring(0, windowChars.clamp(0, raw.length));
  }

  final position = (effectiveSeed.abs()) % maxPositions;
  final start = (position * strideChars).clamp(0, raw.length - 1);
  final end = (start + windowChars).clamp(start + 1, raw.length);
  return raw.substring(start, end);
}

List<String?> _buildContextFallbackOrder({
  required String? initialContext,
  required String? rawLibraryContent,
}) {
  if (rawLibraryContent == null) {
    return [initialContext];
  }

  final candidates = <String?>[
    initialContext,
    sanitizeStudyMaterialForPrompt(rawLibraryContent, maxChars: 1400),
    sanitizeStudyMaterialForPrompt(rawLibraryContent, maxChars: 900),
    null,
  ];

  final deduped = <String?>[];
  for (final candidate in candidates) {
    final text = candidate?.trim();
    if (text == null) {
      if (!deduped.contains(null)) deduped.add(null);
      continue;
    }
    if (text.isEmpty) continue;
    if (deduped.contains(text)) continue;
    deduped.add(text);
  }

  return deduped.isEmpty ? [initialContext] : deduped;
}

final quizGenerationCoordinatorProvider = Provider<QuizGenerationCoordinator>(
  (ref) => QuizGenerationCoordinator(
    ref.watch(quizRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
    observability: ref.watch(appObservabilityProvider),
  ),
);
