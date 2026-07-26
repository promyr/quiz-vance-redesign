import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';

class MasterApiKeyEntry {
  const MasterApiKeyEntry({
    required this.id,
    required this.provider,
    required this.maskedKey,
    required this.label,
    required this.priority,
    required this.isActive,
    required this.healthStatus,
    this.failureCount = 0,
    this.blockedUntil,
    this.lastTestedAt,
    this.lastErrorCode,
    this.createdAt,
  });

  factory MasterApiKeyEntry.fromJson(Map<String, dynamic> json) {
    DateTime? readDate(String key) {
      final value = json[key]?.toString();
      return value == null ? null : DateTime.tryParse(value);
    }

    return MasterApiKeyEntry(
      id: json['id']?.toString() ?? '',
      provider: json['provider'] as String? ?? 'gemini',
      maskedKey: json['masked_key'] as String? ?? '••••••••',
      label: json['label'] as String? ?? 'Chave mestra',
      priority: (json['priority'] as num?)?.toInt() ?? 100,
      isActive: json['is_active'] as bool? ?? false,
      healthStatus: json['health_status'] as String? ?? 'unknown',
      failureCount: (json['failure_count'] as num?)?.toInt() ?? 0,
      blockedUntil: readDate('blocked_until'),
      lastTestedAt: readDate('last_tested_at'),
      lastErrorCode: json['last_error_code'] as String?,
      createdAt: readDate('created_at'),
    );
  }

  final String id;
  final String provider;
  final String maskedKey;
  final String label;
  final int priority;
  final bool isActive;
  final String healthStatus;
  final int failureCount;
  final DateTime? blockedUntil;
  final DateTime? lastTestedAt;
  final String? lastErrorCode;
  final DateTime? createdAt;

  MasterApiKeyEntry copyWith({
    int? priority,
    bool? isActive,
  }) {
    return MasterApiKeyEntry(
      id: id,
      provider: provider,
      maskedKey: maskedKey,
      label: label,
      priority: priority ?? this.priority,
      isActive: isActive ?? this.isActive,
      healthStatus: healthStatus,
      failureCount: failureCount,
      blockedUntil: blockedUntil,
      lastTestedAt: lastTestedAt,
      lastErrorCode: lastErrorCode,
      createdAt: createdAt,
    );
  }
}

class ApiKeyTestResult {
  const ApiKeyTestResult({
    required this.isValid,
    required this.message,
    required this.latencyMs,
    this.errorCode,
  });

  factory ApiKeyTestResult.fromJson(Map<String, dynamic> json) {
    return ApiKeyTestResult(
      isValid: json['is_valid'] as bool? ?? false,
      message: json['message'] as String? ?? 'Teste concluído',
      latencyMs: (json['latency_ms'] as num?)?.toInt() ?? 0,
      errorCode: json['error_code'] as String?,
    );
  }

  final bool isValid;
  final String message;
  final int latencyMs;
  final String? errorCode;
}

class AdminMasterKeysService {
  AdminMasterKeysService({
    required ApiClient client,
    FlutterSecureStorage? storage,
  })  : _client = client,
        _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _client;
  final FlutterSecureStorage _storage;
  static const _legacyPoolKey = 'admin_master_keys_pool';

  Future<void> migrateLegacyLocalPoolIfNeeded({
    required String adminPassword,
  }) async {
    final raw = await _storage.read(key: _legacyPoolKey);
    if (raw == null || raw.trim().isEmpty) return;

    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      throw const FormatException('Pool local legado inválido');
    }

    for (final item in decoded.whereType<Map<String, dynamic>>()) {
      if (item['is_active'] == false) continue;
      final apiKey = item['api_key']?.toString().trim() ?? '';
      if (apiKey.isEmpty) continue;
      await addKey(
        provider: item['provider']?.toString() ?? 'gemini',
        apiKey: apiKey,
        label: item['label']?.toString() ?? 'Chave migrada',
        adminPassword: adminPassword,
      );
    }
    await _storage.delete(key: _legacyPoolKey);
  }

  Future<List<MasterApiKeyEntry>> getAllKeys() async {
    final response = await _client.dio.get(ApiEndpoints.adminAiKeys);
    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Resposta inválida do painel administrativo');
    }
    final keys = raw['keys'];
    if (keys is! List<dynamic>) return const [];
    return keys
        .whereType<Map<String, dynamic>>()
        .map(MasterApiKeyEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> addKey({
    required String provider,
    required String apiKey,
    required String label,
    required String adminPassword,
  }) async {
    await _client.dio.post(
      ApiEndpoints.adminAiKeys,
      data: {
        'provider': provider.trim().toLowerCase(),
        'api_key': apiKey.trim(),
        'label': label.trim(),
      },
      options: _adminOptions(adminPassword),
    );
  }

  Future<void> removeKey(
    String id, {
    required String adminPassword,
  }) async {
    await _client.dio.delete(
      ApiEndpoints.adminAiKey(id),
      options: _adminOptions(adminPassword),
    );
  }

  Future<void> toggleKeyActive(
    String id,
    bool isActive, {
    required String adminPassword,
  }) async {
    await _client.dio.patch(
      ApiEndpoints.adminAiKey(id),
      data: {'is_active': isActive},
      options: _adminOptions(adminPassword),
    );
  }

  Future<void> reorderKeys(
    List<MasterApiKeyEntry> reorderedList, {
    required String adminPassword,
  }) async {
    final updated = <MasterApiKeyEntry>[];
    try {
      for (var index = 0; index < reorderedList.length; index++) {
        final entry = reorderedList[index];
        await _client.dio.patch(
          ApiEndpoints.adminAiKey(entry.id),
          data: {'priority': (index + 1) * 10},
          options: _adminOptions(adminPassword),
        );
        updated.add(entry);
      }
    } catch (_) {
      for (final entry in updated.reversed) {
        try {
          await _client.dio.patch(
            ApiEndpoints.adminAiKey(entry.id),
            data: {'priority': entry.priority},
            options: _adminOptions(adminPassword),
          );
        } catch (_) {
          // The original failure remains authoritative. A refresh reconciles UI.
        }
      }
      rethrow;
    }
  }

  Future<ApiKeyTestResult> testApiKey(
    String id, {
    required String adminPassword,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.adminAiKeyTest(id),
      options: _adminOptions(adminPassword),
    );
    final raw = response.data;
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Resposta inválida do teste de chave');
    }
    return ApiKeyTestResult.fromJson(raw);
  }

  Options _adminOptions(String adminPassword) {
    if (adminPassword.isEmpty) {
      throw const FormatException('Informe a senha administrativa');
    }
    return Options(headers: {'X-Admin-Password': adminPassword});
  }
}

final adminMasterKeysServiceProvider = Provider<AdminMasterKeysService>((ref) {
  return AdminMasterKeysService(client: ref.watch(apiClientProvider));
});

final adminMasterKeysListProvider =
    FutureProvider.autoDispose<List<MasterApiKeyEntry>>((ref) async {
  final service = ref.watch(adminMasterKeysServiceProvider);
  return service.getAllKeys();
});
