import '../../../core/network/api_error_message.dart';
import 'ai_generation_guard.dart';

bool isRetryableAiGenerationFailure(Object error) {
  final normalized = userVisibleErrorMessage(error, fallback: '')
      .trim()
      .toLowerCase();
  if (normalized.isEmpty) return false;

  return normalized.contains('erro ao gerar') ||
      normalized.contains('nao foi possivel gerar') ||
      normalized.contains('tente novamente') ||
      normalized.contains('chave de api') ||
      normalized.contains('prove') ||
      normalized.contains('modelo') ||
      normalized.contains('autentic') ||
      normalized.contains('quota') ||
      normalized.contains('credito') ||
      normalized.contains('rate limit') ||
      normalized.contains('resource has been exhausted');
}

List<String> buildAiProviderFallbackOrder({
  required String preferredProvider,
  required AiGenerationConfigState config,
}) {
  final providers = <String>['gemini', 'groq', 'openai'];

  if (providers.contains(preferredProvider)) {
    providers.remove(preferredProvider);
    providers.insert(0, preferredProvider);
  }

  return providers;
}
