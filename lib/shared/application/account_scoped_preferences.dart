import 'package:shared_preferences/shared_preferences.dart';

class AccountScopedPreferences {
  AccountScopedPreferences._();

  static final AccountScopedPreferences instance = AccountScopedPreferences._();

  String? _activeAccountId;

  void setActiveAccountId(String? accountId) {
    final normalized = accountId?.trim();
    _activeAccountId =
        normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? get activeAccountId => _activeAccountId;

  String scopedKey(String key) {
    final accountId = _activeAccountId;
    if (accountId == null || accountId.isEmpty) {
      return key;
    }
    return 'account:$accountId:$key';
  }

  Future<String?> getString(
    String key, {
    bool scoped = true,
    bool allowLegacyFallback = true,
  }) => _getValue(
    key,
    scoped: scoped,
    allowLegacyFallback: allowLegacyFallback,
    read: (prefs, storageKey) => prefs.getString(storageKey),
    write: (prefs, storageKey, value) => prefs.setString(storageKey, value),
  );

  Future<int?> getInt(
    String key, {
    bool scoped = true,
    bool allowLegacyFallback = true,
  }) => _getValue(
    key,
    scoped: scoped,
    allowLegacyFallback: allowLegacyFallback,
    read: (prefs, storageKey) => prefs.getInt(storageKey),
    write: (prefs, storageKey, value) => prefs.setInt(storageKey, value),
  );

  Future<bool?> getBool(
    String key, {
    bool scoped = true,
    bool allowLegacyFallback = true,
  }) => _getValue(
    key,
    scoped: scoped,
    allowLegacyFallback: allowLegacyFallback,
    read: (prefs, storageKey) => prefs.getBool(storageKey),
    write: (prefs, storageKey, value) => prefs.setBool(storageKey, value),
  );

  Future<List<String>?> getStringList(
    String key, {
    bool scoped = true,
    bool allowLegacyFallback = true,
  }) => _getValue(
    key,
    scoped: scoped,
    allowLegacyFallback: allowLegacyFallback,
    read: (prefs, storageKey) => prefs.getStringList(storageKey),
    write: (prefs, storageKey, value) => prefs.setStringList(storageKey, value),
  );

  Future<T?> _getValue<T>(
    String key, {
    required bool scoped,
    required bool allowLegacyFallback,
    required T? Function(SharedPreferences preferences, String key) read,
    required Future<bool> Function(
      SharedPreferences preferences,
      String key,
      T value,
    ) write,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final scopedKeyValue = _maybeScopedKey(key, scoped: scoped);
    if (scopedKeyValue != null) {
      final scopedValue = read(prefs, scopedKeyValue);
      if (scopedValue != null) {
        return scopedValue;
      }
      if (allowLegacyFallback) {
        final legacyValue = read(prefs, key);
        if (legacyValue != null) {
          await write(prefs, scopedKeyValue, legacyValue);
          await prefs.remove(key);
          return legacyValue;
        }
      }
      return null;
    }
    if (allowLegacyFallback) {
      return read(prefs, key);
    }
    return null;
  }

  Future<void> setString(String key, String value, {bool scoped = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedKey = _resolvedKey(key, scoped: scoped);
    await prefs.setString(resolvedKey, value);
    if (scoped && resolvedKey != key) {
      await prefs.remove(key);
    }
  }

  Future<void> setInt(String key, int value, {bool scoped = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedKey = _resolvedKey(key, scoped: scoped);
    await prefs.setInt(resolvedKey, value);
    if (scoped && resolvedKey != key) {
      await prefs.remove(key);
    }
  }

  Future<void> setBool(String key, bool value, {bool scoped = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedKey = _resolvedKey(key, scoped: scoped);
    await prefs.setBool(resolvedKey, value);
    if (scoped && resolvedKey != key) {
      await prefs.remove(key);
    }
  }

  Future<void> setStringList(
    String key,
    List<String> value, {
    bool scoped = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resolvedKey = _resolvedKey(key, scoped: scoped);
    await prefs.setStringList(resolvedKey, value);
    if (scoped && resolvedKey != key) {
      await prefs.remove(key);
    }
  }

  Future<void> remove(
    String key, {
    bool scoped = true,
    bool removeLegacyFallback = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_resolvedKey(key, scoped: scoped));
    if (removeLegacyFallback && scoped) {
      await prefs.remove(key);
    }
  }

  Future<void> removeMany(
    List<String> keys, {
    bool scoped = true,
    bool removeLegacyFallback = false,
  }) async {
    for (final key in keys) {
      await remove(
        key,
        scoped: scoped,
        removeLegacyFallback: removeLegacyFallback,
      );
    }
  }

  String _resolvedKey(String key, {required bool scoped}) {
    return _maybeScopedKey(key, scoped: scoped) ?? key;
  }

  String? _maybeScopedKey(String key, {required bool scoped}) {
    if (!scoped) {
      return null;
    }
    final accountId = _activeAccountId;
    if (accountId == null || accountId.isEmpty) {
      return null;
    }
    return 'account:$accountId:$key';
  }
}
