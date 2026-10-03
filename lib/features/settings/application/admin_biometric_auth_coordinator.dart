import '../domain/admin_authorization.dart';

class AdminBiometricUnavailable implements Exception {
  const AdminBiometricUnavailable([
    this.message = 'Biometria indisponível neste aparelho.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class AdminDevicePublicCredential {
  const AdminDevicePublicCredential({
    required this.credentialId,
    required this.publicKey,
    required this.deviceName,
    required this.platform,
  });

  final String credentialId;
  final String publicKey;
  final String deviceName;
  final String platform;
}

class AdminBiometricChallenge {
  const AdminBiometricChallenge({
    required this.challengeId,
    required this.challenge,
  });

  final String challengeId;
  final String challenge;
}

abstract interface class AdminBiometricVault {
  Future<bool> canAuthenticate();

  Future<String?> get credentialId;

  Future<AdminDevicePublicCredential> createCredential();

  Future<String> sign(String challenge);

  Future<void> clear();
}

abstract interface class AdminBiometricRemote {
  Future<bool> isEnrolled(String credentialId);

  Future<void> enroll({
    required AdminDevicePublicCredential credential,
    required String password,
  });

  Future<AdminBiometricChallenge> createChallenge({
    required String credentialId,
    required String scope,
  });

  Future<String> verifyChallenge({
    required String credentialId,
    required String challengeId,
    required String signature,
  });
}

class AdminBiometricAuthCoordinator {
  const AdminBiometricAuthCoordinator({
    required AdminBiometricVault vault,
    required AdminBiometricRemote remote,
  })  : _vault = vault,
        _remote = remote;

  final AdminBiometricVault _vault;
  final AdminBiometricRemote _remote;

  Future<bool> canAuthorize() async {
    if (!await _vault.canAuthenticate()) return false;
    final id = await _vault.credentialId;
    if (id == null || id.isEmpty) return false;
    return _remote.isEnrolled(id);
  }

  Future<void> enroll({required String password}) async {
    if (password.trim().isEmpty) {
      throw const FormatException('Informe a senha administrativa');
    }
    if (!await _vault.canAuthenticate()) {
      throw const AdminBiometricUnavailable();
    }
    await _vault.clear();
    final credential = await _vault.createCredential();
    try {
      await _remote.enroll(credential: credential, password: password);
    } catch (_) {
      await _vault.clear();
      rethrow;
    }
  }

  Future<AdminAuthorization> authorize({
    required AdminStepUpScope scope,
  }) async {
    if (!await _vault.canAuthenticate()) {
      throw const AdminBiometricUnavailable();
    }
    final id = await _vault.credentialId;
    if (id == null || id.isEmpty || !await _remote.isEnrolled(id)) {
      throw const AdminBiometricUnavailable(
        'Ative a biometria neste aparelho antes de utilizá-la.',
      );
    }
    final challenge = await _remote.createChallenge(
      credentialId: id,
      scope: scope.value,
    );
    final signature = await _vault.sign(challenge.challenge);
    final token = await _remote.verifyChallenge(
      credentialId: id,
      challengeId: challenge.challengeId,
      signature: signature,
    );
    return AdminAuthorization.biometric(token);
  }
}
