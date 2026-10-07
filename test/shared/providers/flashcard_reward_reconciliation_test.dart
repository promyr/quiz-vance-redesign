import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:quiz_vance_flutter/shared/providers/gamification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends Mock implements ApiClient {}

class _Dio extends Mock implements Dio {}

void main() {
  test('review reconciles local XP with server including achievement rewards',
      () async {
    SharedPreferences.setMockInitialValues({'gamif_xp': 190, 'gamif_level': 2});
    AccountScopedPreferences.instance.setActiveAccountId(null);
    final api = _Api();
    final dio = _Dio();
    when(() => api.dio).thenReturn(dio);
    when(() => dio.get(ApiEndpoints.userStats)).thenAnswer((_) async =>
        Response(
            requestOptions: RequestOptions(path: ApiEndpoints.userStats),
            data: {'total_xp': 245}));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    await container.read(gamificationProvider.future);
    await container.read(gamificationProvider.notifier).recordFlashcardReview();
    expect(container.read(gamificationProvider).valueOrNull!.totalXp, 245);
  });
}
