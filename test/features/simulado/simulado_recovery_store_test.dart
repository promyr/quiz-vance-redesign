import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/features/simulado/data/simulado_recovery_store.dart';
import 'package:quiz_vance_flutter/features/quiz/domain/question_model.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';

void main() {
  test(
      'tentativa preserva relógio respostas e conta sem ressuscitar após conclusão',
      () async {
    SharedPreferences.setMockInitialValues({});
    final account = AccountScopedPreferences.instance;
    account.setActiveAccountId('alice');
    final store = SimuladoRecoveryStore();
    final start = DateTime(2026, 10, 6, 12);
    final checkpoint = SimuladoCheckpoint(
        sessionId: 'stable',
        questions: [
          Question(
              id: 'q',
              text: 'Questão',
              options: const [QuizOption(id: 'a', text: 'Alternativa')],
              correctOptionId: 'a')
        ],
        durationSeconds: 600,
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 2)),
        answers: {0: 'a'});
    await store.save(checkpoint);
    expect((await store.load())!.startedAt, start);
    expect((await store.load())!.answers[0], 'a');
    expect((await store.load())!.completedAt,
        start.add(const Duration(minutes: 2)));
    account.setActiveAccountId('bob');
    expect(await store.load(), isNull);
    account.setActiveAccountId('alice');
    final save = store.save(checkpoint);
    final clear = store.clear();
    await Future.wait([save, clear]);
    expect(await store.load(), isNull);
  });
}
