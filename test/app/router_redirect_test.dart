import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/app/router.dart';

void main() {
  group('resolveAppRedirect', () {
    test('envia para boot enquanto auth esta carregando', () {
      final redirect = resolveAppRedirect(
        authLoading: true,
        isAuthenticated: false,
        shouldShowOnboardingFlag: false,
        location: '/ranking',
      );

      expect(redirect, '/boot?from=%2Franking');
    });

    test('preserva rota original apos bootstrap autenticado', () {
      final redirect = resolveAppRedirect(
        authLoading: false,
        isAuthenticated: true,
        shouldShowOnboardingFlag: false,
        location: '/boot',
        pendingLocation: '/ranking',
      );

      expect(redirect, '/ranking');
    });

    test('manda para onboarding quando ainda nao exibido', () {
      final redirect = resolveAppRedirect(
        authLoading: false,
        isAuthenticated: false,
        shouldShowOnboardingFlag: true,
        location: '/boot',
      );

      expect(redirect, '/onboarding');
    });

    test('manda para login apos bootstrap desautenticado', () {
      final redirect = resolveAppRedirect(
        authLoading: false,
        isAuthenticated: false,
        shouldShowOnboardingFlag: false,
        location: '/boot',
      );

      expect(redirect, '/login');
    });

    test('nao redireciona usuario autenticado fora do login', () {
      final redirect = resolveAppRedirect(
        authLoading: false,
        isAuthenticated: true,
        shouldShowOnboardingFlag: false,
        location: '/stats',
      );

      expect(redirect, isNull);
    });
  });
}
