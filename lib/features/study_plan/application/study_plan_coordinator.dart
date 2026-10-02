import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/ai_generation_guard.dart';
import '../data/study_plan_repository.dart';
import '../domain/study_plan_model.dart';
import '../domain/study_plan_notice_analysis.dart';

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

  /// Retorna as sessões programadas para a data atual (ou customizada).
  List<StudyPlanItem> getTodaySessions(StudyPlan plan, {DateTime? customDate}) {
    final today = customDate ?? DateTime.now();
    return plan.getSessionsForDate(today);
  }

  /// Retorna sessões pendentes em atraso de dias anteriores.
  List<StudyPlanItem> getOverdueSessions(StudyPlan plan, {DateTime? customDate}) {
    final today = customDate ?? DateTime.now();
    return plan.getOverduePendingSessions(today);
  }

  Future<StudyPlan> generatePlan({
    required String objective,
    String? examDate,
    required int tempoDiario,
    required String rawTopics,
    List<String>? reviewedTopics,
    List<int> sourceDocumentIds = const [],
  }) async {
    final trimmedObjective = objective.trim();
    if (trimmedObjective.isEmpty) {
      throw const StudyPlanValidationException(
        'Informe seu objetivo de estudo.',
      );
    }

    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    final topics = reviewedTopics ??
        rawTopics
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
      sourceDocumentIds: sourceDocumentIds,
    );
  }

  Future<StudyPlanNoticeAnalysis> analyzeNotice({
    String? jobTitle,
    CargoNoticeItem? selectedCargo,
    required String noticeText,
  }) async {
    final normalizedJobTitle = jobTitle?.trim() ?? '';
    final normalizedNoticeText = noticeText.trim();
    if (normalizedNoticeText.isEmpty) {
      throw const StudyPlanValidationException(
        'Selecione um edital em PDF.',
      );
    }

    final provider = await _aiGenerationGuard.ensureReadyForGeneration();
    return _studyPlanRepository.analyzeNotice(
      jobTitle: normalizedJobTitle,
      selectedCargo: selectedCargo,
      noticeText: normalizedNoticeText,
      aiProvider: provider,
    );
  }

  Future<StudyPlan> toggleItem({
    required StudyPlan plan,
    required int index,
  }) {
    return _studyPlanRepository.toggleItem(plan, index);
  }

  Future<StudyPlan> updateSessionResult({
    required String planId,
    required String sessionId,
    required StudySessionStatus status,
    int? correctAnswers,
    int? incorrectAnswers,
    int? timeSpentMinutes,
    double? score,
  }) {
    return _studyPlanRepository.updateSessionResult(
      planId: planId,
      sessionId: sessionId,
      status: status,
      correctAnswers: correctAnswers,
      incorrectAnswers: incorrectAnswers,
      timeSpentMinutes: timeSpentMinutes,
      score: score,
    );
  }

  Future<void> setActivePlan(String planId) {
    return _studyPlanRepository.setActivePlan(planId);
  }

  Future<StudyPlan> rescheduleSession({
    required String planId,
    required String sessionId,
    required String newScheduledDate,
  }) {
    return _studyPlanRepository.rescheduleSession(
      planId: planId,
      sessionId: sessionId,
      newScheduledDate: newScheduledDate,
    );
  }

  Future<StudyPlan> carryOverOverdueSessions({
    required String planId,
    DateTime? customDate,
  }) {
    final today = customDate ?? DateTime.now();
    return _studyPlanRepository.carryOverOverdueSessions(
      planId: planId,
      today: today,
    );
  }
}

final studyPlanCoordinatorProvider = Provider<StudyPlanCoordinator>(
  (ref) => StudyPlanCoordinator(
    ref.watch(studyPlanRepositoryProvider),
    aiGenerationGuard: ref.watch(aiGenerationGuardProvider),
  ),
);
