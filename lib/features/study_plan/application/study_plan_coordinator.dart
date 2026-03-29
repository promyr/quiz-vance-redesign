import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/ai_generation_guard.dart';
import '../data/study_plan_repository.dart';
import '../domain/study_plan_model.dart';

class StudyPlanValidationException implements Exception {
  const StudyPlanValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StudyPlanCoordinator {
  const StudyPlanCoordinator(
    this._studyPlanRepository, {
    required AiGenerationGuard aiGenerationGuard,
  }) : _aiGenerationGuard = aiGenerationGuard;

  final StudyPlanRepository _studyPlanRepository;
  final AiGenerationGuard _aiGenerationGuard;

  Future<StudyPlan> generatePlan({
    required String objective,
    String? examDate,
    required int tempoDiario,
    required String rawTopics,
  }) async {
    final trimmedObjective = objective.trim();
    if (trimmedObjective.isEmpty) {
      throw const StudyPlanValidationException(
        'Informe seu objetivo de estudo.',
      );
    }

    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    final topics = rawTopics
        .split(',')
        .map((topic) => topic.trim())
        .where((topic) => topic.isNotEmpty)
        .toList();

    return _studyPlanRepository.generatePlan(
      objetivo: trimmedObjective,
      dataProva: examDate?.trim().isEmpty ?? true ? null : examDate!.trim(),
      tempoDiario: tempoDiario,
      topicos: topics,
      aiProvider: provider,
    );
  }

  Future<StudyPlan> toggleItem({
    required StudyPlan plan,
    required int index,
  }) {
    return _studyPlanRepository.toggleItem(plan, index);
  }
}

final studyPlanCoordinatorProvider = Provider<StudyPlanCoordinator>(
  (ref) => StudyPlanCoordinator(
    ref.watch(studyPlanRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
  ),
);
