import '../../quiz/domain/quiz_generation_params.dart';
import '../domain/study_plan_model.dart';

QuizGenerationParams studyPlanQuizRequest(StudyPlan plan, StudyPlanItem item) {
  final subject = item.effectiveSubject.trim();
  final topics =
      item.subtopics.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
  final topic = topics.isNotEmpty
      ? '$subject: ${topics.join('; ')}'
      : item.tema.trim().isNotEmpty && item.tema.trim() != subject
          ? (item.tema.startsWith('$subject:')
              ? item.tema.trim()
              : '$subject: ${item.tema.trim()}')
          : subject;
  final documentIds = item.sourceDocumentIds.isNotEmpty
      ? item.sourceDocumentIds
      : plan.sourceDocumentIds;
  return QuizGenerationParams(
      topic: topic,
      difficulty: item.difficulty,
      aiProvider: null,
      documentId: documentIds.isEmpty ? null : documentIds.first,
      planId: plan.id,
      studySessionId: item.effectiveSessionId);
}
