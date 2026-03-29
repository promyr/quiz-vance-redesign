import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/ai_provider_catalog.dart';

const _secureStorage = FlutterSecureStorage();

enum SyncFeedbackState { fullSuccess, localOnly, failure }

class SyncFeedbackResult {
  const SyncFeedbackResult({
    required this.state,
    required this.message,
  });

  final SyncFeedbackState state;
  final String message;

  bool get isFullSuccess => state == SyncFeedbackState.fullSuccess;
  bool get isLocalOnly => state == SyncFeedbackState.localOnly;
}

Map<String, dynamic> buildAiConfigPayload({
  required String provider,
  String? geminiKey,
  String? openaiKey,
  String? groqKey,
}) {
  return {
    'provider': provider,
    'model': defaultModelForAiProvider(provider),
    if (geminiKey != null && geminiKey.trim().isNotEmpty)
      'api_key_gemini': geminiKey.trim(),
    if (openaiKey != null && openaiKey.trim().isNotEmpty)
      'api_key_openai': openaiKey.trim(),
    if (groqKey != null && groqKey.trim().isNotEmpty)
      'api_key_groq': groqKey.trim(),
  };
}

/// Provider que expoe o provedor de IA selecionado.
final aiProviderSettingProvider =
    FutureProvider.autoDispose<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('ai_provider') ?? 'gemini';
});

/// Provider que expoe a chave de API do Gemini.
final apiKeyGeminiProvider = FutureProvider.autoDispose<String>((ref) async {
  return await _secureStorage.read(key: 'api_key_gemini') ?? '';
});

/// Provider que expoe a chave de API do OpenAI.
final apiKeyOpenaiProvider = FutureProvider.autoDispose<String>((ref) async {
  return await _secureStorage.read(key: 'api_key_openai') ?? '';
});

/// Provider que expoe a chave de API do Groq.
final apiKeyGroqProvider = FutureProvider.autoDispose<String>((ref) async {
  return await _secureStorage.read(key: 'api_key_groq') ?? '';
});
