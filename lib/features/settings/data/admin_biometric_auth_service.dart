import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../application/admin_biometric_auth_coordinator.dart';

const _credentialIdStorageKey = 'admin_biometric_credential_id';
const _biometricVaultName = 'quiz_vance_admin_signing_key_v1';

String _encodeBytes(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');

List<int> _decodeBytes(String value) =>
    base64Url.decode(base64Url.normalize(value));

class DeviceAdminBiometricVault implements AdminBiometricVault {
  DeviceAdminBiometricVault({
    BiometricStorage? biometricStorage,
    FlutterSecureStorage? metadataStorage,
    Ed25519? algorithm,
  })  : _biometricStorage = biometricStorage ?? BiometricStorage(),
        _metadataStorage = metadataStorage ?? const FlutterSecureStorage(),
        _algorithm = algorithm ?? Ed25519();

  final BiometricStorage _biometricStorage;
  final FlutterSecureStorage _metadataStorage;
  final Ed25519 _algorithm;

  static const _prompt = PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Confirmar ação administrativa',
      subtitle: 'Use sua digital para continuar',
      negativeButton: 'Usar senha',
    ),
  );

  @override
  Future<bool> canAuthenticate() async {
    if (!Platform.isAndroid) return false;
    return await _biometricStorage.canAuthenticate() ==
        CanAuthenticateResponse.success;
  }

  @override
  Future<String?> get credentialId =>
      _metadataStorage.read(key: _credentialIdStorageKey);

  Future<BiometricStorageFile> _vault() {
    return _biometricStorage.getStorage(
      _biometricVaultName,
      options: StorageFileInitOptions(
        authenticationRequired: true,
        androidBiometricOnly: true,
        authenticationValidityDurationSeconds: 15,
      ),
      promptInfo: _prompt,
    );
  }

  @override
  Future<AdminDevicePublicCredential> createCredential() async {
    if (!await canAuthenticate()) {
      throw const AdminBiometricUnavailable();
    }
    final keyPair = await _algorithm.newKeyPair();
    final keyData = await keyPair.extract();
    final credentialId = _encodeBytes(
      List<int>.generate(24, (_) => Random.secure().nextInt(256)),
    );
    final payload = jsonEncode({
      'credential_id': credentialId,
      'private_key': _encodeBytes(keyData.bytes),
      'public_key': _encodeBytes(keyData.publicKey.bytes),
    });
    final vault = await _vault();
    await vault.write(payload);
    await _metadataStorage.write(
      key: _credentialIdStorageKey,
      value: credentialId,
    );
    return AdminDevicePublicCredential(
      credentialId: credentialId,
      publicKey: _encodeBytes(keyData.publicKey.bytes),
      deviceName: 'Quiz Vance Android',
      platform: 'android',
    );
  }

  @override
  Future<void> clear() async {
    try {
      await (await _vault()).delete();
    } catch (_) {
      // A chave do Android Keystore pode ter sido invalidada após mudanças
      // de biometria, restauração do aparelho ou reinstalação.
    }
    await _metadataStorage.delete(key: _credentialIdStorageKey);
  }

  @override
  Future<String> sign(String challenge) async {
    try {
      final vault = await _vault();
      final raw = await vault.read();
      if (raw == null || raw.isEmpty) {
        throw const AdminBiometricUnavailable(
          'A credencial biométrica deste aparelho não foi encontrada.',
        );
      }
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Credencial biométrica inválida');
      }
      final privateKey = _decodeBytes(data['private_key']?.toString() ?? '');
      final publicKey = _decodeBytes(data['public_key']?.toString() ?? '');
      final keyPair = SimpleKeyPairData(
        privateKey,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      );
      final signature = await _algorithm.sign(
        _decodeBytes(challenge),
        keyPair: keyPair,
      );
      return _encodeBytes(signature.bytes);
    } on AdminBiometricUnavailable {
      rethrow;
    } on BiometricStorageException {
      await clear();
      throw const AdminBiometricUnavailable(
        'A credencial biométrica expirou. Ative a digital novamente.',
      );
    } on PlatformException {
      await clear();
      throw const AdminBiometricUnavailable(
        'A credencial biométrica expirou. Ative a digital novamente.',
      );
    } on FormatException {
      await clear();
      throw const AdminBiometricUnavailable(
        'A credencial biométrica expirou. Ative a digital novamente.',
      );
    }
  }
}

class ApiAdminBiometricRemote implements AdminBiometricRemote {
  const ApiAdminBiometricRemote(this._client);

  final ApiClient _client;

  @override
  Future<bool> isEnrolled(String credentialId) async {
    final response = await _client.dio.get(
      ApiEndpoints.adminBiometricCredentialStatus,
      queryParameters: {'credential_id': credentialId},
    );
    final data = response.data;
    return data is Map<String, dynamic> && data['enrolled'] == true;
  }

  @override
  Future<void> enroll({
    required AdminDevicePublicCredential credential,
    required String password,
  }) async {
    await _client.dio.post(
      ApiEndpoints.adminBiometricCredentials,
      data: {
        'credential_id': credential.credentialId,
        'public_key': credential.publicKey,
        'device_name': credential.deviceName,
        'platform': credential.platform,
      },
      options: Options(headers: {'X-Admin-Password': password}),
    );
  }

  @override
  Future<AdminBiometricChallenge> createChallenge({
    required String credentialId,
    required String scope,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.adminBiometricChallenges,
      data: {'credential_id': credentialId, 'scope': scope},
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Desafio biométrico inválido');
    }
    return AdminBiometricChallenge(
      challengeId: data['challenge_id']?.toString() ?? '',
      challenge: data['challenge']?.toString() ?? '',
    );
  }

  @override
  Future<String> verifyChallenge({
    required String credentialId,
    required String challengeId,
    required String signature,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.adminBiometricChallengeVerify,
      data: {
        'credential_id': credentialId,
        'challenge_id': challengeId,
        'signature': signature,
      },
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Autorização biométrica inválida');
    }
    return data['step_up_token']?.toString() ?? '';
  }
}

final adminBiometricVaultProvider = Provider<AdminBiometricVault>((ref) {
  return DeviceAdminBiometricVault();
});

final adminBiometricRemoteProvider = Provider<AdminBiometricRemote>((ref) {
  return ApiAdminBiometricRemote(ref.watch(apiClientProvider));
});

final adminBiometricAuthCoordinatorProvider =
    Provider<AdminBiometricAuthCoordinator>((ref) {
  return AdminBiometricAuthCoordinator(
    vault: ref.watch(adminBiometricVaultProvider),
    remote: ref.watch(adminBiometricRemoteProvider),
  );
});
