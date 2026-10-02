import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/core/exceptions/premium_limit_exception.dart';
import 'package:quiz_vance_flutter/core/exceptions/provider_rate_limit_exception.dart';
import 'package:quiz_vance_flutter/features/settings/data/ai_generation_fallback.dart';

void main() {
  test('never retries a product quota exhausted by the user', () {
    expect(
      isRetryableAiGenerationFailure(
        const PremiumLimitException('Limite diario atingido.'),
      ),
      isFalse,
    );
  });

  test('retries a provider capacity failure', () {
    expect(
      isRetryableAiGenerationFailure(
        const ProviderRateLimitException('Provider rate limit exceeded.'),
      ),
      isTrue,
    );
  });
}
