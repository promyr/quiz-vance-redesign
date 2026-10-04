import '../../quiz/domain/question_model.dart';
import 'error_question.dart';

class ReviewSuggestion {
  const ReviewSuggestion(this.topic, this.questions);
  final String topic;
  final List<Question> questions;
}

ReviewSuggestion? suggestErrorReview(List<ErrorQuestion> errors) {
  final groups = <String, List<ErrorQuestion>>{};
  for (final error in errors.where((e) => !e.isMastered)) {
    groups
        .putIfAbsent(
            error.topic.trim().isEmpty
                ? 'Revisão de erros'
                : error.topic.trim(),
            () => [])
        .add(error);
  }
  if (groups.isEmpty) return null;
  int score(List<ErrorQuestion> group) =>
      group.fold(0, (sum, e) => sum + e.timesFailed.clamp(1, 1000));
  final ordered = groups.entries.toList()
    ..sort((a, b) => score(b.value).compareTo(score(a.value)));
  final chosen = ordered.first;
  final questions = chosen.value.toList()
    ..sort((a, b) {
      final byErrors = b.timesFailed.compareTo(a.timesFailed);
      return byErrors != 0 ? byErrors : b.failedAt.compareTo(a.failedAt);
    });
  final unique = <String, Question>{};
  for (final error in questions) {
    unique.putIfAbsent(error.question.id, () => error.question);
  }
  return ReviewSuggestion(chosen.key, unique.values.take(10).toList());
}
