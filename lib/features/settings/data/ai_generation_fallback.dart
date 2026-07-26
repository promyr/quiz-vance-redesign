import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/exceptions/provider_rate_limit_exception.dart';
import '../../../core/network/api_error_message.dart';

bool isRetryableAiGenerationFailure(Object error) {
  if (error is PremiumLimitException) return false;
  if (error is ProviderRateLimitException) return true;

  final normalized =
      userVisibleErrorMessage(error, fallback: '').trim().toLowerCase();
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
