import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/features/quiz/providers/recent_subjects_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId('user_test_123');
  });

  test('adiciona materias mantendo a ordem mais recente primeiro', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Aguarda inicializacao
    await container.read(recentSubjectsProvider.future);

    final notifier = container.read(recentSubjectsProvider.notifier);
    await notifier.addSubject('Java');
    await notifier.addSubject('Direito Constitucional');
    await notifier.addSubject('Português');

    final list = await container.read(recentSubjectsProvider.future);
    expect(list, ['Português', 'Direito Constitucional', 'Java']);
  });

  test('move materia existente para o topo sem duplicar', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(recentSubjectsProvider.future);

    final notifier = container.read(recentSubjectsProvider.notifier);
    await notifier.addSubject('Java');
    await notifier.addSubject('Python');
    await notifier.addSubject('java'); // insensitivo

    final list = await container.read(recentSubjectsProvider.future);
    expect(list, ['java', 'Python']);
  });

  test('remove materia da lista', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(recentSubjectsProvider.future);

    final notifier = container.read(recentSubjectsProvider.notifier);
    await notifier.addSubject('Java');
    await notifier.addSubject('Python');
    await notifier.removeSubject('Java');

    final list = await container.read(recentSubjectsProvider.future);
    expect(list, ['Python']);
  });

  test('isola materias por conta ativa', () async {
    final container1 = ProviderContainer();
    await container1.read(recentSubjectsProvider.future);
    await container1.read(recentSubjectsProvider.notifier).addSubject('Java');
    expect(await container1.read(recentSubjectsProvider.future), ['Java']);
    container1.dispose();

    // Troca para outra conta
    AccountScopedPreferences.instance.setActiveAccountId('user_other_456');

    final container2 = ProviderContainer();
    final list2 = await container2.read(recentSubjectsProvider.future);
    expect(list2, isEmpty);
    await container2.read(recentSubjectsProvider.notifier).addSubject('Flutter');
    expect(await container2.read(recentSubjectsProvider.future), ['Flutter']);
    container2.dispose();
  });
}
