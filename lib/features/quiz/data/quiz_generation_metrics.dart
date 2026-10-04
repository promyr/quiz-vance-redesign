import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/application/account_scoped_preferences.dart';

/// Local bounded diagnostics: no topic, PDF text, questions or credentials.
class QuizGenerationMetrics {
  QuizGenerationMetrics()
      : _key = AccountScopedPreferences.instance
            .scopedKey('quiz_generation_metrics_v1');
  final String _key;
  static Future<void>? _pending;
  Future<Map<String, dynamic>> _read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      return raw == null
          ? {}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> samples() async {
    final pending = _pending;
    if (pending != null) await pending;
    final data = await _read();
    return (data['samples'] as List? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();
  }

  Future<void> record(
      {required int durationMs,
      required bool success,
      required List<String> texts}) {
    final previous = _pending;
    late final Future<void> operation;
    operation = () async {
      if (previous != null) await previous;
      try {
        final data = await _read();
        final hashes = (data['hashes'] as List? ?? []).cast<String>().toList();
        var duplicates = 0;
        for (final text in texts) {
          final normalized =
              text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
          final hash = (await Sha256().hash(utf8.encode(normalized)))
              .bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          if (hashes.contains(hash)) {
            duplicates++;
          } else {
            hashes.add(hash);
          }
        }
        final records = (data['samples'] as List? ?? []).toList()
          ..add({
            'at': DateTime.now().toIso8601String(),
            'durationMs': durationMs,
            'success': success,
            'count': texts.length,
            'duplicates': duplicates
          });
        await (await SharedPreferences.getInstance()).setString(
            _key,
            jsonEncode({
              'samples': records
                  .skip((records.length - 30).clamp(0, records.length))
                  .toList(),
              'hashes': hashes
                  .skip((hashes.length - 200).clamp(0, hashes.length))
                  .toList()
            }));
      } catch (_) {/* Diagnostics cannot break generation. */} finally {
        if (identical(_pending, operation)) _pending = null;
      }
    }();
    _pending = operation;
    return operation;
  }
}
