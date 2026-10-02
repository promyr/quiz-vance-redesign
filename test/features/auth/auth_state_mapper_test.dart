import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/auth/application/auth_state_mapper.dart';

void main() {
  group('authStateFromUser', () {
    test('normaliza identidade e privilegio administrativo', () {
      final state = authStateFromUser(<String, dynamic>{
        'id': 42,
        'login_id': '  ProMyr  ',
        'email': 'belchior@example.com',
        'name': 'Belchior',
        'avatar_url': 'https://example.com/avatar.png',
        'role': ' ADMIN ',
      });

      expect(state.isAuthenticated, isTrue);
      expect(state.userId, '42');
      expect(state.loginId, 'ProMyr');
      expect(state.role, 'admin');
      expect(state.isAdmin, isTrue);
    });

    test('usa user_id e preserva papeis nao administrativos normalizados', () {
      final state = authStateFromUser(<String, dynamic>{
        'user_id': 'user-7',
        'login_id': 'aluno',
        'role': ' Premium ',
      });

      expect(state.userId, 'user-7');
      expect(state.role, 'premium');
      expect(state.isPremium, isTrue);
    });

    test('aplica valores seguros quando o payload esta incompleto', () {
      final state = authStateFromUser(const <String, dynamic>{});

      expect(state.isAuthenticated, isTrue);
      expect(state.loginId, isEmpty);
      expect(state.role, 'user');
      expect(state.isAdmin, isFalse);
    });
  });
}
