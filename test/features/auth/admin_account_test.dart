import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/storage/local_storage.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}
class _MockLocalStorage extends Mock implements LocalStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockApiClient apiClient;
  late _MockLocalStorage storage;
  late AuthRepository authRepository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    apiClient = _MockApiClient();
    storage = _MockLocalStorage();
    when(() => apiClient.saveTokens(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        )).thenAnswer((_) async {});
    when(() => storage.setCacheValue(any(), any(), scoped: any(named: 'scoped')))
        .thenAnswer((_) async {});
    authRepository = AuthRepository(
      apiClient,
      storage: storage,
    );
  });

  test('admin/admin login succeeds locally with max level user', () async {
    final result = await authRepository.login(
      loginId: 'admin',
      password: 'admin',
    );

    expect(result['user'], isNotNull);
    final user = result['user'] as Map<String, dynamic>;
    expect(user['login_id'], 'admin');
    expect(user['name'], contains('Administrador'));
    expect(user['plan_type'], 'premium');
    expect(user['premium_active'], isTrue);
    expect(user['level'], 100);
    expect(user['xp'], 99999);
    expect(user['streak_days'], 365);
  });
}
