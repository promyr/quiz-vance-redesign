import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/features/conquistas/data/achievement_repository.dart';
import 'package:quiz_vance_flutter/features/conquistas/domain/achievement_catalog.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';

class DelayedAchievements extends AchievementRepository {
  DelayedAchievements() : super(ApiClient());
  final response = Completer<List<String>>();
  @override
  Future<List<String>> getAchievements() => response.future;
  @override
  Future<void> unlock(AchievementDefinition achievement) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resposta remota atrasada não apaga conquista ganha depois do boot',
      () async {
    SharedPreferences.setMockInitialValues({});
    AccountScopedPreferences.instance.setActiveAccountId('merge-qa');
    addTearDown(
        () => AccountScopedPreferences.instance.setActiveAccountId(null));
    final repo = DelayedAchievements();
    final container = ProviderContainer(
        overrides: [achievementRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await container.read(gamificationProvider.future);
    await container.read(gamificationProvider.notifier).incrementTotalQuizzes();
    final firstName = achievementDisplayName(achievementCatalog.first);
    expect(
        container.read(gamificationProvider).requireValue.unlockedAchievements,
        contains(firstName));
    repo.response.complete(['10_questoes']);
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(
        container.read(gamificationProvider).requireValue.unlockedAchievements,
        containsAll(
            [firstName, achievementDisplayName(achievementCatalog[1])]));
    expect(
        await AccountScopedPreferences.instance
            .getStringList('gamif_achievements'),
        containsAll(
            [firstName, achievementDisplayName(achievementCatalog[1])]));
  });
}
