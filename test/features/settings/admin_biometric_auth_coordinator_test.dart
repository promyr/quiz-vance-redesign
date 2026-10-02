import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/settings/application/admin_biometric_auth_coordinator.dart';
import 'package:quiz_vance_flutter/features/settings/domain/admin_authorization.dart';

void main() {
  test('enrolls a device credential without persisting the admin password',
      () async {
    final vault = _FakeVault();
    final remote = _FakeRemote();
    final coordinator = AdminBiometricAuthCoordinator(
      vault: vault,
      remote: remote,
    );

    await coordinator.enroll(password: 'admin-password');

    expect(vault.clearCalls, 1);
    expect(remote.enrolledCredentialId, 'device-credential-1');
    expect(remote.enrolledPublicKey, 'public-key');
    expect(remote.enrollmentPassword, 'admin-password');
    expect(vault.passwordWrites, 0);
  });

  test('signs the server challenge and returns a scoped step-up header',
      () async {
    final vault = _FakeVault()..storedCredentialId = 'device-credential-1';
    final remote = _FakeRemote()..enrolled = true;
    final coordinator = AdminBiometricAuthCoordinator(
      vault: vault,
      remote: remote,
    );

    final authorization = await coordinator.authorize(
      scope: AdminStepUpScope.deleteAiKey,
    );

    expect(vault.signedChallenge, 'challenge-value');
    expect(remote.verifiedSignature, 'signed:challenge-value');
    expect(remote.verifiedScope, 'ai_key.delete');
    expect(
      authorization.headers,
      const {'X-Admin-Step-Up': 'one-use-step-up-token'},
    );
  });

  test('reports unavailable when the platform has no biometric protection',
      () async {
    final coordinator = AdminBiometricAuthCoordinator(
      vault: _FakeVault()..available = false,
      remote: _FakeRemote(),
    );

    expect(await coordinator.canAuthorize(), isFalse);
    expect(
      () => coordinator.authorize(scope: AdminStepUpScope.testAiKey),
      throwsA(isA<AdminBiometricUnavailable>()),
    );
  });

  test('password authorization uses only the password header', () {
    final authorization = AdminAuthorization.password(' admin-password ');

    expect(
      authorization.headers,
      const {'X-Admin-Password': ' admin-password '},
    );
  });
}

class _FakeVault implements AdminBiometricVault {
  bool available = true;
  String? storedCredentialId;
  String? signedChallenge;
  int passwordWrites = 0;
  int clearCalls = 0;

  @override
  Future<bool> canAuthenticate() async => available;

  @override
  Future<void> clear() async {
    clearCalls++;
    storedCredentialId = null;
  }

  @override
  Future<AdminDevicePublicCredential> createCredential() async {
    storedCredentialId = 'device-credential-1';
    return const AdminDevicePublicCredential(
      credentialId: 'device-credential-1',
      publicKey: 'public-key',
      deviceName: 'Test device',
      platform: 'android',
    );
  }

  @override
  Future<String?> get credentialId async => storedCredentialId;

  @override
  Future<String> sign(String challenge) async {
    signedChallenge = challenge;
    return 'signed:$challenge';
  }
}

class _FakeRemote implements AdminBiometricRemote {
  bool enrolled = false;
  String? enrolledCredentialId;
  String? enrolledPublicKey;
  String? enrollmentPassword;
  String? verifiedSignature;
  String? verifiedScope;

  @override
  Future<AdminBiometricChallenge> createChallenge({
    required String credentialId,
    required String scope,
  }) async {
    verifiedScope = scope;
    return const AdminBiometricChallenge(
      challengeId: 'challenge-id',
      challenge: 'challenge-value',
    );
  }

  @override
  Future<void> enroll({
    required AdminDevicePublicCredential credential,
    required String password,
  }) async {
    enrolledCredentialId = credential.credentialId;
    enrolledPublicKey = credential.publicKey;
    enrollmentPassword = password;
    enrolled = true;
  }

  @override
  Future<bool> isEnrolled(String credentialId) async => enrolled;

  @override
  Future<String> verifyChallenge({
    required String credentialId,
    required String challengeId,
    required String signature,
  }) async {
    verifiedSignature = signature;
    return 'one-use-step-up-token';
  }
}
