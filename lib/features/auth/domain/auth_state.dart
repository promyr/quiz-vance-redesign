class AuthState {
  static const _unset = Object();

  const AuthState({
    required this.isAuthenticated,
    this.userId,
    this.loginId,
    this.email,
    this.name,
    this.avatarUrl,
  });

  factory AuthState.unauthenticated() =>
      const AuthState(isAuthenticated: false);

  final bool isAuthenticated;
  final String? userId;
  final String? loginId;
  final String? email;
  final String? name;
  final String? avatarUrl;

  AuthState copyWith({
    bool? isAuthenticated,
    Object? userId = _unset,
    Object? loginId = _unset,
    Object? email = _unset,
    Object? name = _unset,
    Object? avatarUrl = _unset,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      loginId: identical(loginId, _unset) ? this.loginId : loginId as String?,
      email: identical(email, _unset) ? this.email : email as String?,
      name: identical(name, _unset) ? this.name : name as String?,
      avatarUrl:
          identical(avatarUrl, _unset) ? this.avatarUrl : avatarUrl as String?,
    );
  }
}
