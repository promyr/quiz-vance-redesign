String buildAccountScopedStoragePrefix(String accountId) {
  return 'account:$accountId:';
}

String buildMaybeScopedStorageKey({
  required String baseKey,
  String? accountId,
}) {
  final normalized = accountId?.trim();
  if (normalized == null || normalized.isEmpty) {
    return baseKey;
  }
  return '${buildAccountScopedStoragePrefix(normalized)}$baseKey';
}
