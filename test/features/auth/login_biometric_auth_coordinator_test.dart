import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/auth/application/login_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/auth/data/login_biometric_vault.dart';

void main() {
  test('login vault keeps one short authentication window for token rotation',
      () {
    expect(loginBiometricAuthenticationValiditySeconds, greaterThan(0));
  });

  test('stores a refresh session without storing the password', () async {
    final vault = _FakeLoginBiometricVault();
    final coordinator = LoginBiometricAuthCoordinator(vault);

    await coordinator.enroll(
      refreshToken: 'refresh-token',
      loginId: 'promyr',
    );

    expect(vault.savedSession?.refreshToken, 'refresh-token');
    expect(vault.savedSession?.loginId, 'promyr');
  });

  test('rejects an empty refresh token', () async {
    final coordinator =
        LoginBiometricAuthCoordinator(_FakeLoginBiometricVault());

    await expectLater(
      coordinator.enroll(refreshToken: ' ', loginId: 'promyr'),
      throwsA(isA<FormatException>()),
    );
  });

  test('unlocks only when biometrics and a saved session are available',
      () async {
    final vault = _FakeLoginBiometricVault()
      ..savedSession = const LoginBiometricSession(
        refreshToken: 'refresh-token',
        loginId: 'promyr',
      );
    final coordinator = LoginBiometricAuthCoordinator(vault);

    expect(await coordinator.canUnlock(), isTrue);
    expect((await coordinator.unlock()).loginId, 'promyr');

    vault.available = false;
    expect(await coordinator.canUnlock(), isFalse);
  });

  test('updates an existing protected session without enrolling again',
      () async {
    final vault = _FakeLoginBiometricVault()
      ..savedSession = const LoginBiometricSession(
        refreshToken: 'old-refresh',
        loginId: 'promyr',
      );
    final coordinator = LoginBiometricAuthCoordinator(vault);

    await coordinator.updateSession(
      refreshToken: 'new-refresh',
      loginId: 'promyr',
    );

    expect(vault.savedSession?.refreshToken, 'new-refresh');
    expect(vault.writeCount, 1);
  });

  test('classifies an empty protected token as an invalid credential',
      () async {
    final vault = _FakeLoginBiometricVault()
      ..savedSession = const LoginBiometricSession(
        refreshToken: ' ',
        loginId: 'promyr',
      );
    final coordinator = LoginBiometricAuthCoordinator(vault);

    await expectLater(
      coordinator.unlock(),
      throwsA(isA<LoginBiometricCredentialInvalid>()),
    );
  });

  test('classifies a native operation that never completes as timeout',
      () async {
    final coordinator = LoginBiometricAuthCoordinator(
      _HangingLoginBiometricVault(),
      operationTimeout: const Duration(milliseconds: 5),
    );

    await expectLater(
      coordinator.canUnlock(),
      throwsA(isA<LoginBiometricTimedOut>()),
    );
  });

  test('serializes protected vault writes and cleanup', () async {
    final vault = _ControlledLoginBiometricVault();
    final coordinator = LoginBiometricAuthCoordinator(vault);

    final enrollment = coordinator.enroll(
      refreshToken: 'refresh-token',
      loginId: 'promyr',
    );
    await vault.writeStarted.future;
    final cleanup = coordinator.clear();

    await Future<void>.delayed(Duration.zero);
    expect(vault.clearCount, 0);

    vault.releaseWrite.complete();
    await Future.wait([enrollment, cleanup]);
    expect(vault.clearCount, 1);
  });
}

class _HangingLoginBiometricVault implements LoginBiometricVault {
  @override
  Future<bool> canAuthenticate() => Completer<bool>().future;

  @override
  Future<void> clear() async {}

  @override
  Future<bool> hasSession() async => true;

  @override
  Future<LoginBiometricSession> read() async =>
      const LoginBiometricSession(refreshToken: 'token', loginId: 'promyr');

  @override
  Future<void> write(LoginBiometricSession session) async {}
}

class _ControlledLoginBiometricVault extends _FakeLoginBiometricVault {
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();
  int clearCount = 0;

  @override
  Future<void> write(LoginBiometricSession session) async {
    writeStarted.complete();
    await releaseWrite.future;
    await super.write(session);
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    await super.clear();
  }
}

class _FakeLoginBiometricVault implements LoginBiometricVault {
  bool available = true;
  LoginBiometricSession? savedSession;
  int writeCount = 0;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<void> clear() async => savedSession = null;

  @override
  Future<bool> hasSession() async => savedSession != null;

  @override
  Future<LoginBiometricSession> read() async {
    final session = savedSession;
    if (session == null) throw const LoginBiometricUnavailable();
    return session;
  }

  @override
  Future<void> write(LoginBiometricSession session) async {
    writeCount += 1;
    savedSession = session;
  }
}
