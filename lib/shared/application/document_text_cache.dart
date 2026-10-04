import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_scoped_preferences.dart';

/// Extracted documents are immutable per ID. Cache expires after one day,
/// retains at most three documents and never saves failed/empty responses.
class DocumentTextCache {
  static final Map<String, Future<String>> _pending = {};
  String _key(int id) =>
      AccountScopedPreferences.instance.scopedKey('document_text_v1_$id');
  Future<String> get(int id, Future<String> Function() fetch) async {
    final key = _key(id);
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return fetch();
    }
    try {
      final raw = prefs.getString(key);
      if (raw != null) {
        final data = jsonDecode(raw) as Map;
        if (DateTime.now().millisecondsSinceEpoch - (data['at'] as int) <
            const Duration(days: 1).inMilliseconds) {
          return data['text'] as String;
        }
      }
    } catch (_) {
      await prefs.remove(key);
    }
    if (_pending.containsKey(key)) return _pending[key]!;
    final operation = () async {
      final text = await fetch();
      if (text.trim().isNotEmpty && text.length <= 1000000) {
        final prefix = key.substring(0, key.lastIndexOf('_') + 1);
        final keys = prefs
            .getKeys()
            .where((k) => k.startsWith(prefix) && k != key)
            .toList();
        keys.sort(
            (a, b) => _timestamp(prefs, a).compareTo(_timestamp(prefs, b)));
        while (keys.length >= 3) {
          await prefs.remove(keys.removeAt(0));
        }
        await prefs.setString(
            key,
            jsonEncode(
                {'at': DateTime.now().millisecondsSinceEpoch, 'text': text}));
      }
      return text;
    }();
    _pending[key] = operation;
    try {
      return await operation;
    } finally {
      _pending.remove(key);
    }
  }

  int _timestamp(SharedPreferences prefs, String key) {
    try {
      return (jsonDecode(prefs.getString(key)!) as Map)['at'] as int;
    } catch (_) {
      return 0;
    }
  }

  Future<void> invalidate(int id) async {
    final key = _key(id);
    try {
      await _pending[key];
    } catch (_) {}
    try {
      await (await SharedPreferences.getInstance()
              .timeout(const Duration(seconds: 3)))
          .remove(key);
    } catch (_) {/* Cache invalidation cannot undo a completed deletion. */}
  }
}
