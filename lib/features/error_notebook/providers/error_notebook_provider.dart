import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../quiz/domain/question_model.dart';
import '../data/error_notebook_repository.dart';
import '../domain/error_question.dart';

class ErrorNotebookNotifier extends AsyncNotifier<List<ErrorQuestion>> {
  @override
  Future<List<ErrorQuestion>> build() async {
    final repo = ref.watch(errorNotebookRepositoryProvider);
    return repo.getErrorQuestions();
  }

  Future<void> recordWrongQuestions({
    required List<QuestionAnswer> wrongAnswers,
    required String topic,
  }) async {
    final repo = ref.read(errorNotebookRepositoryProvider);
    await repo.recordWrongQuestions(
      wrongAnswers: wrongAnswers,
      topic: topic,
    );
    ref.invalidateSelf();
  }

  Future<void> markQuestionMastered(String questionId) async {
    final repo = ref.read(errorNotebookRepositoryProvider);
    await repo.markQuestionMastered(questionId);
    ref.invalidateSelf();
  }

  Future<void> clearMastered() async {
    final repo = ref.read(errorNotebookRepositoryProvider);
    await repo.clearMastered();
    ref.invalidateSelf();
  }
}

final errorNotebookNotifierProvider =
    AsyncNotifierProvider<ErrorNotebookNotifier, List<ErrorQuestion>>(
  ErrorNotebookNotifier.new,
);

final errorNotebookCountProvider = Provider<int>((ref) {
  final asyncState = ref.watch(errorNotebookNotifierProvider);
  return asyncState.valueOrNull?.length ?? 0;
});
