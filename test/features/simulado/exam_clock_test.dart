import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/simulado/domain/exam_clock.dart';

void main() {
  test('reconciles elapsed time after background pause', () {
    final start = DateTime.utc(2026, 7, 25, 12);
    final clock = ExamClock(durationSeconds: 3600, startedAt: start);
    expect(
      clock.remainingSecondsAt(start.add(const Duration(minutes: 17))),
      2580,
    );
    expect(clock.remainingSecondsAt(start.add(const Duration(hours: 2))), 0);
  });
}
