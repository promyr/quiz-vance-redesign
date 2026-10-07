import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/application/account_scoped_preferences.dart';
import '../../quiz/domain/question_model.dart';

class SimuladoCheckpoint {
  const SimuladoCheckpoint(
      {required this.sessionId,
      required this.questions,
      required this.durationSeconds,
      required this.startedAt,
      this.completedAt,
      this.currentIndex = 0,
      this.answers = const {}});
  final String sessionId;
  final List<Question> questions;
  final int durationSeconds;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int currentIndex;
  final Map<int, String> answers;
  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'questions': questions.map((q) => q.toJson()).toList(),
        'durationSeconds': durationSeconds,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'currentIndex': currentIndex,
        'answers': answers.map((k, v) => MapEntry('$k', v)),
      };
  factory SimuladoCheckpoint.fromJson(Map<String, dynamic> data) {
    final questions = (data['questions'] as List)
        .map((q) => Question.fromJson(Map<String, dynamic>.from(q as Map)))
        .toList();
    final index = data['currentIndex'] as int;
    final duration = data['durationSeconds'] as int;
    if (questions.isEmpty ||
        index < 0 ||
        index >= questions.length ||
        duration <= 0) {
      throw const FormatException('Sessão de simulado inválida.');
    }
    final answers = (data['answers'] as Map)
        .map((k, v) => MapEntry(int.parse(k as String), v as String));
    if (answers.entries.any((e) =>
        e.key < 0 ||
        e.key >= questions.length ||
        !questions[e.key].options.any((o) => o.id == e.value))) {
      throw const FormatException('Respostas do simulado inválidas.');
    }
    return SimuladoCheckpoint(
        sessionId: data['sessionId'] as String,
        questions: questions,
        durationSeconds: duration,
        startedAt: DateTime.parse(data['startedAt'] as String),
        completedAt: data['completedAt'] == null
            ? null
            : DateTime.parse(data['completedAt'] as String),
        currentIndex: index,
        answers: answers);
  }
}

/// Checkpoint separado dos quizzes, isolado por conta e com escritas ordenadas.
class SimuladoRecoveryStore {
  static final revision = ValueNotifier<int>(0);
  static Future<void>? _writes;
  String get _key =>
      AccountScopedPreferences.instance.scopedKey('simulado_active_v1');
  Future<SimuladoCheckpoint?> load() async {
    final key = _key;
    await _writes;
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    try {
      return SimuladoCheckpoint.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(SimuladoCheckpoint session) =>
      _change(jsonEncode(session.toJson()));
  Future<void> clear() => _change(null);
  Future<void> _change(String? encoded) {
    final key = _key;
    late Future<void> tail;
    final operation = (_writes ?? Future<void>.value()).then((_) async {
      try {
      final prefs = await SharedPreferences.getInstance();
      final ok = encoded == null
          ? await prefs.remove(key)
          : await prefs.setString(key, encoded);
      if (!ok) {
        throw StateError('Não foi possível salvar a tentativa do simulado.');
      }
      revision.value++;
      } finally {
        if (identical(_writes, tail)) _writes = null;
      }
    });
    tail = operation.catchError((Object _) {});
    _writes = tail;
    return operation;
  }
}
