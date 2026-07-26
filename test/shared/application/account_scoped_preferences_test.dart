import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AccountScopedPreferences prefs;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    prefs = AccountScopedPreferences.instance;
    prefs.setActiveAccountId(null);
  });

  test('scopedKey returns un-prefixed key when no active account', () {
    expect(prefs.scopedKey('ai_provider'), 'ai_provider');
  });

  test('scopedKey prefixes key when account is active', () {
    prefs.setActiveAccountId('user_123');
    expect(prefs.scopedKey('ai_provider'), 'account:user_123:ai_provider');
  });

  test('setString and getString operate under active account scope', () async {
    prefs.setActiveAccountId('acc_A');
    await prefs.setString('ai_provider', 'openai');

    expect(await prefs.getString('ai_provider'), 'openai');

    // Switch account to acc_B
    prefs.setActiveAccountId('acc_B');
    expect(await prefs.getString('ai_provider'), isNull);

    await prefs.setString('ai_provider', 'groq');
    expect(await prefs.getString('ai_provider'), 'groq');

    // Switch back to acc_A
    prefs.setActiveAccountId('acc_A');
    expect(await prefs.getString('ai_provider'), 'openai');
  });

  test('migrates legacy un-scoped key to scoped key on read', () async {
    SharedPreferences.setMockInitialValues({
      'streak_count': 5,
    });

    prefs.setActiveAccountId('user_legacy');
    final count = await prefs.getInt('streak_count');

    expect(count, 5);
    // Verified that scoped value was written
    final rawPrefs = await SharedPreferences.getInstance();
    expect(rawPrefs.getInt('account:user_legacy:streak_count'), 5);
    expect(rawPrefs.getInt('streak_count'), isNull);
  });
}
