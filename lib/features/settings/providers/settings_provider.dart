import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/account_scoped_preferences.dart';
import '../domain/ai_provider_catalog.dart';

final aiProviderSettingProvider =
    FutureProvider.autoDispose<String>((ref) async {
  final stored =
      await AccountScopedPreferences.instance.getString('ai_provider');
  return normalizeAiProviderId(stored ?? defaultAiProviderId);
});
