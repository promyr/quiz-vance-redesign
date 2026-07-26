class ExamClock {
  ExamClock({
    required int durationSeconds,
    required DateTime startedAt,
  })  : totalSeconds = durationSeconds,
        deadline = startedAt.add(Duration(seconds: durationSeconds));

  final int totalSeconds;
  final DateTime deadline;

  int remainingSecondsAt(DateTime now) {
    final milliseconds = deadline.difference(now).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / 1000).ceil().clamp(0, totalSeconds);
  }

  int elapsedSecondsAt(DateTime now) => totalSeconds - remainingSecondsAt(now);
}
