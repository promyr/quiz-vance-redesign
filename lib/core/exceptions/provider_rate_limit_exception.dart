/// The configured AI provider is temporarily unable to serve generation.
///
/// This is intentionally distinct from [PremiumLimitException]: provider
/// capacity can be retried or routed elsewhere, while a user's product quota
/// must stop without consuming more requests.
class ProviderRateLimitException implements Exception {
  const ProviderRateLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isProviderRateLimitMessage(String message) {
  final normalized = message.trim().toLowerCase();
  const providerMarkers = <String>[
    'provider',
    'provedor',
    'rate limit',
    'resource_exhausted',
    'resource has been exhausted',
    'quota exceeded',
    'credit',
    'credito',
    'crédito',
    'gemini',
    'openai',
    'groq',
  ];
  return providerMarkers.any(normalized.contains);
}
