import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/application/account_scoped_preferences.dart';

/// Small, account-isolated checkpoints. Serial writes prevent stale saves
/// from resurrecting a checkpoint after completion.
class QuizRecoveryStore {
  static Future<void>? _writes;
  String get _key =>
      AccountScopedPreferences.instance.scopedKey('quiz_recovery_v1');
  Future<Map<String, dynamic>> _read(String key) async {
    try {
      final raw = (await SharedPreferences.getInstance()
              .timeout(const Duration(seconds: 3)))
          .getString(key);
      return raw == null
          ? {}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> load(String session) async {
    final key = _key;
    final pending = _writes;
    if (pending != null) await pending;
    final entry = (await _read(key))[session];
    if (entry is! Map || entry['savedAt'] is! int) return null;
    if (DateTime.now().millisecondsSinceEpoch - (entry['savedAt'] as int) >
        const Duration(days: 7).inMilliseconds) {
      return null;
    }
    final data = entry['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  Future<Map<String, dynamic>?> latest() async {
    final key = _key;
    final pending = _writes;
    if (pending != null) await pending;
    final entries = (await _read(key)).entries.toList().reversed;
    for (final entry in entries) {
      final value = entry.value;
      if (value is Map &&
          value['savedAt'] is int &&
          DateTime.now().millisecondsSinceEpoch - (value['savedAt'] as int) <=
              const Duration(days: 7).inMilliseconds &&
          value['data'] is Map) {
        return {
          'key': entry.key,
          'data': Map<String, dynamic>.from(value['data'] as Map)
        };
      }
    }
    return null;
  }

  Future<void> save(String session, Map<String, dynamic> data) =>
      _change(session, data);
  Future<void> clear(String session) => _change(session, null);
  Future<void> _change(String session, Map<String, dynamic>? data) {
    final key = _key;
    final encoded = data == null ? null : jsonEncode(data);
    final previous = _writes;
    late final Future<void> operation;
    operation = () async {
      if (previous != null) await previous;
      try {
        final values = await _read(key);
        values.remove(session);
        if (encoded != null) {
          values[session] = {
            'savedAt': DateTime.now().millisecondsSinceEpoch,
            'data': jsonDecode(encoded)
          };
        }
        while (values.length > 8) {
          values.remove(values.keys.first);
        }
        final prefs = await SharedPreferences.getInstance()
            .timeout(const Duration(seconds: 3));
        await prefs.setString(key, jsonEncode(values));
      } catch (_) {
        /* Local storage failure must not block the quiz. */
      } finally {
        if (identical(_writes, operation)) _writes = null;
      }
    }();
    _writes = operation;
    return operation;
  }
}
