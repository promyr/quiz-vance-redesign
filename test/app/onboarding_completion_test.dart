import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quiz_vance_flutter/app/router.dart';
import 'package:quiz_vance_flutter/features/auth/data/auth_repository.dart';
import 'package:quiz_vance_flutter/features/auth/application/login_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/auth/data/login_biometric_vault.dart';

class _Auth extends Mock implements AuthRepository {}

class _Biometrics extends Mock implements LoginBiometricAuthCoordinator {}

void main() {
  for (final skip in [true, false]) {
    testWidgets('concluir apresentação abre login sem reiniciar (pular $skip)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final auth = _Auth();
      final biometrics = _Biometrics();
      when(() => auth.restorePersistedSession())
          .thenAnswer((_) async => const PersistedAuthSession.none());
      when(() => auth.getCachedUser()).thenAnswer((_) async => null);
      when(() => biometrics.canUnlock()).thenAnswer((_) async => false);
      final container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        loginBiometricAuthCoordinatorProvider.overrideWithValue(biometrics),
      ]);
      addTearDown(container.dispose);
      final router = container.read(routerProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/onboarding');
      if (skip) {
        await tester.tap(find.text('Pular'));
      } else {
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Próximo →'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Começar agora'));
      }
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(await container.read(onboardingGateProvider.future), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
