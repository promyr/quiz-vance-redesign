import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/account_scoped_preferences.dart';
import '../domain/ai_provider_catalog.dart';

const _aiProviderPreferenceKey = 'ai_provider';

class AiGenerationGuard {
  AiGenerationGuard({AccountScopedPreferences? preferences})
      : _preferences = preferences ?? AccountScopedPreferences.instance;

  final AccountScopedPreferences _preferences;

  Future<String> ensureReadyForGeneration({
    String? overrideProvider,
  }) async {
    final selected = overrideProvider ??
        await _preferences.getString(_aiProviderPreferenceKey) ??
        defaultAiProviderId;
    return normalizeAiProviderId(selected);
  }
}

final aiGenerationGuardProvider = Provider<AiGenerationGuard>(
  (ref) => AiGenerationGuard(),
);
