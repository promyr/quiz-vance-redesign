enum PremiumEntryMode {
  manage,
  subscribe,
}

PremiumEntryMode premiumEntryModeFromQuery(String? raw) {
  final normalized = raw?.trim().toLowerCase();
  switch (normalized) {
    case 'manage':
      return PremiumEntryMode.manage;
    case 'subscribe':
    default:
      return PremiumEntryMode.subscribe;
  }
}

String premiumRouteForEntry(PremiumEntryMode mode) {
  return '/premium?entry=${mode.name}';
}
