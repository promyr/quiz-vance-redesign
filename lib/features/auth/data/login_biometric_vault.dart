import 'dart:convert';
import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/login_biometric_auth_coordinator.dart';

const _loginVaultName = 'quiz_vance_login_refresh_v1';
const _loginVaultMarkerKey = 'login_biometric_session_configured';
const loginBiometricAuthenticationValiditySeconds = 10;

class DeviceLoginBiometricVault implements LoginBiometricVault {
  DeviceLoginBiometricVault({
    BiometricStorage? biometricStorage,
    FlutterSecureStorage? metadataStorage,
  })  : _biometricStorage = biometricStorage ?? BiometricStorage(),
        _metadataStorage = metadataStorage ?? const FlutterSecureStorage();

  final BiometricStorage _biometricStorage;
  final FlutterSecureStorage _metadataStorage;

  static const _prompt = PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Entrar no Quiz Vance',
      subtitle: 'Use sua digital para acessar sua conta',
      negativeButton: 'Usar senha',
    ),
  );

  @override
  Future<bool> canAuthenticate() async {
    if (!Platform.isAndroid) return false;
    return await _biometricStorage.canAuthenticate() ==
        CanAuthenticateResponse.success;
  }

  Future<BiometricStorageFile> _vault() {
    return _biometricStorage.getStorage(
      _loginVaultName,
      options: StorageFileInitOptions(
        authenticationRequired: true,
        androidBiometricOnly: true,
        authenticationValidityDurationSeconds:
            loginBiometricAuthenticationValiditySeconds,
      ),
      promptInfo: _prompt,
    );
  }

  @override
  Future<bool> hasSession() async {
    if (!await canAuthenticate()) return false;
    return await _metadataStorage.read(key: _loginVaultMarkerKey) == 'true';
  }

  @override
  Future<LoginBiometricSession> read() async {
    try {
      final raw = await (await _vault()).read();
      if (raw == null || raw.trim().isEmpty) {
        throw const LoginBiometricCredentialInvalid();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const LoginBiometricCredentialInvalid();
      }
      return LoginBiometricSession(
        refreshToken: decoded['refresh_token']?.toString() ?? '',
        loginId: decoded['login_id']?.toString() ?? '',
      );
    } on AuthException catch (error) {
      throw _translateAuthException(error);
    } on FormatException {
      throw const LoginBiometricCredentialInvalid();
    } on BiometricStorageException {
      throw const LoginBiometricCredentialInvalid();
    }
  }

  @override
  Future<void> write(LoginBiometricSession session) async {
    try {
      await (await _vault()).write(
        jsonEncode({
          'refresh_token': session.refreshToken,
          'login_id': session.loginId,
        }),
      );
      await _metadataStorage.write(
        key: _loginVaultMarkerKey,
        value: 'true',
      );
    } on AuthException catch (error) {
      throw _translateAuthException(error);
    } on BiometricStorageException {
      throw const LoginBiometricCredentialInvalid();
    }
  }

  @override
  Future<void> clear() async {
    try {
      await (await _vault()).delete();
    } catch (_) {
      // Limpeza local best-effort em aparelhos sem biometria ativa.
    }
    await _metadataStorage.delete(key: _loginVaultMarkerKey);
  }
}

LoginBiometricException _translateAuthException(AuthException error) {
  switch (error.code) {
    case AuthExceptionCode.userCanceled:
    case AuthExceptionCode.canceled:
      return const LoginBiometricCancelled();
    case AuthExceptionCode.timeout:
      return const LoginBiometricTimedOut();
    case AuthExceptionCode.unknown:
    case AuthExceptionCode.linuxAppArmorDenied:
      return const LoginBiometricCredentialInvalid();
  }
}

final loginBiometricVaultProvider = Provider<LoginBiometricVault>((ref) {
  return DeviceLoginBiometricVault();
});

final loginBiometricAuthCoordinatorProvider =
    Provider<LoginBiometricAuthCoordinator>((ref) {
  return LoginBiometricAuthCoordinator(
    ref.watch(loginBiometricVaultProvider),
  );
});
