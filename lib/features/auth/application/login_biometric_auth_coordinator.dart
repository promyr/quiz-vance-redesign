import 'dart:async';

abstract class LoginBiometricException implements Exception {
  const LoginBiometricException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LoginBiometricUnavailable extends LoginBiometricException {
  const LoginBiometricUnavailable([
    super.message = 'Biometria indisponivel neste aparelho.',
  ]);
}

class LoginBiometricCancelled extends LoginBiometricException {
  const LoginBiometricCancelled()
      : super('Leitura da digital cancelada. Use sua senha para continuar.');
}

class LoginBiometricTimedOut extends LoginBiometricException {
  const LoginBiometricTimedOut()
      : super(
          'O tempo para leitura da digital terminou. Tente novamente ou use sua senha.',
        );
}

class LoginBiometricCredentialInvalid extends LoginBiometricException {
  const LoginBiometricCredentialInvalid()
      : super(
          'A credencial biometrica deste aparelho nao e mais valida. Entre com sua senha.',
        );
}

class LoginBiometricSession {
  const LoginBiometricSession({
    required this.refreshToken,
    required this.loginId,
  });

  final String refreshToken;
  final String loginId;
}

abstract interface class LoginBiometricVault {
  Future<bool> canAuthenticate();
  Future<bool> hasSession();
  Future<void> write(LoginBiometricSession session);
  Future<LoginBiometricSession> read();
  Future<void> clear();
}

class LoginBiometricAuthCoordinator {
  LoginBiometricAuthCoordinator(
    this._vault, {
    Duration operationTimeout = const Duration(seconds: 8),
  }) : _operationTimeout = operationTimeout;

  final LoginBiometricVault _vault;
  final Duration _operationTimeout;
  Future<void> _operationTail = Future<void>.value();

  Future<T> _runExclusive<T>(Future<T> Function() operation) {
    final queuedOperation = _operationTail.then<T>((_) => operation());
    _operationTail = queuedOperation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return queuedOperation.timeout(_operationTimeout).onError((error, stackTrace) {
      if (error is TimeoutException) {
        throw const LoginBiometricTimedOut();
      }
      final nonNullError = error ?? StateError('Falha biometrica desconhecida');
      Error.throwWithStackTrace(nonNullError, stackTrace);
    });
  }

  Future<bool> canAuthenticate() {
    return _runExclusive(_vault.canAuthenticate);
  }

  Future<bool> canUnlock() {
    return _runExclusive(() async {
      return await _vault.canAuthenticate() && await _vault.hasSession();
    });
  }

  Future<void> enroll({
    required String refreshToken,
    required String loginId,
  }) {
    return _runExclusive(() async {
      final token = refreshToken.trim();
      if (token.isEmpty) {
        throw const FormatException('Token de renovacao ausente');
      }
      if (!await _vault.canAuthenticate()) {
        throw const LoginBiometricUnavailable();
      }
      await _vault.write(
        LoginBiometricSession(
          refreshToken: token,
          loginId: loginId.trim().toLowerCase(),
        ),
      );
    });
  }

  Future<void> updateSession({
    required String refreshToken,
    required String loginId,
  }) {
    return _runExclusive(() async {
      final token = refreshToken.trim();
      if (token.isEmpty) {
        throw const FormatException('Token de renovacao ausente');
      }
      final canUnlock =
          await _vault.canAuthenticate() && await _vault.hasSession();
      if (!canUnlock) {
        throw const LoginBiometricCredentialInvalid();
      }
      await _vault.write(
        LoginBiometricSession(
          refreshToken: token,
          loginId: loginId.trim().toLowerCase(),
        ),
      );
    });
  }

  Future<LoginBiometricSession> unlock() {
    return _runExclusive(() async {
      final canUnlock =
          await _vault.canAuthenticate() && await _vault.hasSession();
      if (!canUnlock) {
        throw const LoginBiometricUnavailable(
          'Nenhum login por digital foi configurado neste aparelho.',
        );
      }
      final session = await _vault.read();
      if (session.refreshToken.trim().isEmpty) {
        throw const LoginBiometricCredentialInvalid();
      }
      return session;
    });
  }

  Future<void> clear() => _runExclusive(_vault.clear);
}
