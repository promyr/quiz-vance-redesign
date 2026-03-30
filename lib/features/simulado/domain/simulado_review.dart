import '../../quiz/domain/question_model.dart';

List<QuestionAnswer> reviewableSimuladoAnswers(QuizResult result) {
  return result.answers
      .where((answer) => !answer.isCorrect)
      .toList(growable: false);
}
