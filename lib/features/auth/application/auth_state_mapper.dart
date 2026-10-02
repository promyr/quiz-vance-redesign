import '../domain/auth_state.dart';

AuthState authStateFromUser(Map<String, dynamic> data) {
  final loginId = data['login_id']?.toString().trim() ?? '';
  final rawRole = data['role']?.toString().trim().toLowerCase() ?? 'user';
  final role = rawRole == 'admin' ? 'admin' : rawRole;

  return AuthState(
    isAuthenticated: true,
    userId: data['id']?.toString() ?? data['user_id']?.toString(),
    loginId: loginId,
    email: data['email']?.toString(),
    name: data['name']?.toString(),
    avatarUrl: data['avatar_url']?.toString(),
    role: role,
  );
}
