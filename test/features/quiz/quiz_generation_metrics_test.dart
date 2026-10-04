import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_generation_metrics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('records duration, failure and duplicate counts without question text',
      () async {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId('alice');
    final metrics = QuizGenerationMetrics();
    await metrics.record(
        durationMs: 1200, success: true, texts: ['Questao A', 'Questao A']);
    await metrics.record(durationMs: 400, success: false, texts: []);
    final samples = await metrics.samples();
    expect(samples.first['duplicates'], 1);
    expect(samples.last['success'], false);
    expect(samples.first['durationMs'], 1200);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('account:alice:quiz_generation_metrics_v1'),
        isNot(contains('Questao A')));
    AccountScopedPreferences.instance.setActiveAccountId('bob');
    expect(await QuizGenerationMetrics().samples(), isEmpty);
  });
}
