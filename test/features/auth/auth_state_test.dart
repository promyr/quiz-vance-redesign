import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/auth/domain/auth_state.dart';

void main() {
  group('AuthState', () {
    test('creates authenticated AuthState with all fields', () {
      const state = AuthState(
        isAuthenticated: true,
        userId: 'user_123',
        loginId: 'john.doe',
        email: 'user@example.com',
        name: 'John Doe',
        avatarUrl: 'https://cdn.quizvance.app/avatar.png',
      );

      expect(state.isAuthenticated, isTrue);
      expect(state.userId, equals('user_123'));
      expect(state.loginId, equals('john.doe'));
      expect(state.email, equals('user@example.com'));
      expect(state.name, equals('John Doe'));
      expect(
        state.avatarUrl,
        equals('https://cdn.quizvance.app/avatar.png'),
      );
    });

    test('creates unauthenticated state via factory', () {
      final state = AuthState.unauthenticated();

      expect(state.isAuthenticated, isFalse);
      expect(state.userId, isNull);
      expect(state.loginId, isNull);
      expect(state.email, isNull);
      expect(state.name, isNull);
      expect(state.avatarUrl, isNull);
    });

    test('copyWith updates isAuthenticated', () {
      const state = AuthState(isAuthenticated: false);
      final updated = state.copyWith(isAuthenticated: true);

      expect(updated.isAuthenticated, isTrue);
    });

    test('copyWith updates userId', () {
      const state = AuthState(isAuthenticated: false);
      final updated = state.copyWith(userId: 'new_user');

      expect(updated.userId, equals('new_user'));
      expect(updated.isAuthenticated, equals(state.isAuthenticated));
    });

    test('copyWith updates email', () {
      const state = AuthState(isAuthenticated: false);
      final updated = state.copyWith(email: 'new@example.com');

      expect(updated.email, equals('new@example.com'));
    });

    test('copyWith updates loginId', () {
      const state = AuthState(isAuthenticated: false);
      final updated = state.copyWith(loginId: 'novo.id');

      expect(updated.loginId, equals('novo.id'));
    });

    test('copyWith updates name', () {
      const state = AuthState(isAuthenticated: false);
      final updated = state.copyWith(name: 'Jane Doe');

      expect(updated.name, equals('Jane Doe'));
    });

    test('copyWith updates avatarUrl', () {
      const state = AuthState(isAuthenticated: false);
      final updated = state.copyWith(
        avatarUrl: 'https://cdn.quizvance.app/new.png',
      );

      expect(updated.avatarUrl, equals('https://cdn.quizvance.app/new.png'));
    });

    test('copyWith allows clearing avatarUrl', () {
      const state = AuthState(
        isAuthenticated: true,
        avatarUrl: 'https://cdn.quizvance.app/current.png',
      );
      final updated = state.copyWith(avatarUrl: null);

      expect(updated.avatarUrl, isNull);
    });

    test('copyWith with multiple fields', () {
      const state = AuthState(
        isAuthenticated: false,
        userId: 'old_user',
        loginId: 'old.id',
        email: 'old@example.com',
        name: 'Old Name',
        avatarUrl: 'https://cdn.quizvance.app/old.png',
      );

      final updated = state.copyWith(
        isAuthenticated: true,
        userId: 'new_user',
        loginId: 'new.id',
        email: 'new@example.com',
        name: 'New Name',
        avatarUrl: 'https://cdn.quizvance.app/new.png',
      );

      expect(updated.isAuthenticated, isTrue);
      expect(updated.userId, equals('new_user'));
      expect(updated.loginId, equals('new.id'));
      expect(updated.email, equals('new@example.com'));
      expect(updated.name, equals('New Name'));
      expect(updated.avatarUrl, equals('https://cdn.quizvance.app/new.png'));
    });

    test('copyWith preserves unmodified fields', () {
      const state = AuthState(
        isAuthenticated: true,
        userId: 'user_123',
        loginId: 'user.id',
        email: 'user@example.com',
        name: 'John Doe',
        avatarUrl: 'https://cdn.quizvance.app/current.png',
      );

      final updated = state.copyWith(name: 'Jane Doe');

      expect(updated.isAuthenticated, isTrue);
      expect(updated.userId, equals('user_123'));
      expect(updated.loginId, equals('user.id'));
      expect(updated.email, equals('user@example.com'));
      expect(updated.name, equals('Jane Doe'));
      expect(
          updated.avatarUrl, equals('https://cdn.quizvance.app/current.png'));
    });
  });
}
