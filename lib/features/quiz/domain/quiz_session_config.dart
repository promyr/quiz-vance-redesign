import 'quiz_session_logic.dart';

class QuizSessionConfig {
  const QuizSessionConfig({
    required this.topic,
    required this.difficulty,
    required this.aiProvider,
    this.context,
    this.infiniteMode = false,
    this.batchSize = infiniteQuizBatchSize,
  });

  final String topic;
  final String difficulty;
  final String aiProvider;
  final String? context;
  final bool infiniteMode;
  final int batchSize;
}
