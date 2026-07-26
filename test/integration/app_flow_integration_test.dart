import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/app/app.dart';
import 'package:quiz_vance_flutter/shared/application/account_scoped_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'ai_provider': 'gemini',
    });
    AccountScopedPreferences.instance.setActiveAccountId(null);
  });

  testWidgets('E2E: App boots up and renders main application root safely',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: QuizVanceApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify MaterialApp.router is rendered cleanly
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
