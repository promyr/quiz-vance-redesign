import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../domain/ai_provider_catalog.dart';
import '../providers/settings_provider.dart';

const _aiProviderPrefKey = 'ai_provider';
const _aiConfigSyncPendingKey = 'ai_config_sync_pending';
const _aiConfigSyncedProviderKey = 'ai_config_synced_provider';

class AiGenerationConfigState {
  const AiGenerationConfigState({
    required this.selectedProvider,
    required this.selectedProviderLabel,
    required this.selectedProviderKey,
    required this.geminiKey,
    required this.openaiKey,
    required this.groqKey,
    required this.syncPending,
    required this.lastSyncedProvider,
  });

  final String selectedProvider;
  final String selectedProviderLabel;
  final String selectedProviderKey;
  final String geminiKey;
  final String openaiKey;
  final String groqKey;
  final bool syncPending;
  final String? lastSyncedProvider;

  bool get hasSelectedProviderKey => selectedProviderKey.trim().isNotEmpty;
}

class AiGenerationGuard {
  const AiGenerationGuard(
    this._client, {
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final ApiClient _client;
  final FlutterSecureStorage _storage;

  Future<AiGenerationConfigState> loadConfig({
    String? overrideProvider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final selectedProvider =
        (overrideProvider ?? prefs.getString(_aiProviderPrefKey) ?? 'gemini')
            .trim()
            .toLowerCase();

    final values = await Future.wait([
      _storage.read(key: 'api_key_gemini'),
      _storage.read(key: 'api_key_openai'),
      _storage.read(key: 'api_key_groq'),
    ]);

    final geminiKey = values[0] ?? '';
    final openaiKey = values[1] ?? '';
    final groqKey = values[2] ?? '';

    final selectedKey = switch (selectedProvider) {
      'openai' => openaiKey,
      'groq' => groqKey,
      _ => geminiKey,
    };

    return AiGenerationConfigState(
      selectedProvider: selectedProvider,
      selectedProviderLabel: _providerLabelFor(selectedProvider),
      selectedProviderKey: selectedKey,
      geminiKey: geminiKey,
      openaiKey: openaiKey,
      groqKey: groqKey,
      syncPending: prefs.getBool(_aiConfigSyncPendingKey) ?? false,
      lastSyncedProvider: prefs.getString(_aiConfigSyncedProviderKey),
    );
  }

  Future<void> markSyncPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiConfigSyncPendingKey, true);
  }

  Future<void> markSyncSucceeded({
    required String provider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiConfigSyncPendingKey, false);
    await prefs.setString(_aiConfigSyncedProviderKey, provider);
  }

  Future<bool> trySyncCurrentConfig({
    String? overrideProvider,
  }) async {
    try {
      await syncCurrentConfig(overrideProvider: overrideProvider);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncCurrentConfig({
    String? overrideProvider,
  }) async {
    final config = await loadConfig(overrideProvider: overrideProvider);

    if (!config.hasSelectedProviderKey) {
      throw RemoteServiceException(
        'O provedor ${config.selectedProviderLabel} está selecionado, mas a chave dele não foi configurada.',
      );
    }

    await markSyncPending();

    try {
      await _client.dio.post(
        ApiEndpoints.userAiConfig,
        data: buildAiConfigPayload(
          provider: config.selectedProvider,
          geminiKey: config.geminiKey,
          openaiKey: config.openaiKey,
          groqKey: config.groqKey,
        ),
      );

      await markSyncSucceeded(provider: config.selectedProvider);
    } on DioException catch (error) {
      throw buildRemoteServiceException(
        error,
        fallback:
            'Não foi possível sincronizar a configuração de IA com o servidor. Abra Chaves de API e salve novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor para sincronizar a configuração de IA. Verifique sua conexão e tente novamente.',
      );
    }
  }

  Future<String> ensureReadyForGeneration({
    String? overrideProvider,
  }) async {
    final config = await loadConfig(overrideProvider: overrideProvider);

    if (!config.hasSelectedProviderKey) {
      throw RemoteServiceException(
        'O provedor ${config.selectedProviderLabel} está selecionado, mas a chave dele não foi configurada. Abra Chaves de API e salve a credencial antes de gerar conteúdo.',
      );
    }

    final needsSync = config.syncPending ||
        config.lastSyncedProvider == null ||
        config.lastSyncedProvider != config.selectedProvider;

    if (needsSync) {
      await syncCurrentConfig(overrideProvider: config.selectedProvider);
    }

    return config.selectedProvider;
  }
}

String _providerLabelFor(String provider) {
  for (final candidate in aiProviderCatalog) {
    if (candidate.id == provider) return candidate.label;
  }
  return provider.toUpperCase();
}

final aiGenerationGuardProvider = Provider<AiGenerationGuard>(
  (ref) => AiGenerationGuard(ref.watch(apiClientProvider)),
);
