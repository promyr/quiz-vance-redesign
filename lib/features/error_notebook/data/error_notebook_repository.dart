import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_storage.dart';
import '../../quiz/domain/question_model.dart';
import '../domain/error_question.dart';

const _kErrorNotebookStorageKey = 'error_notebook_questions_v1';

class ErrorNotebookRepository {
  ErrorNotebookRepository([LocalStorage? storage])
      : _storage = storage ?? LocalStorage.instance;

  final LocalStorage _storage;

  List<ErrorQuestion> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ErrorQuestion.fromJson)
        .toList();
  }

  Future<void> _update(
      List<ErrorQuestion> Function(List<ErrorQuestion>) update) {
    return _storage.updateCacheValue(_kErrorNotebookStorageKey, (raw) {
      final items = update(_decode(raw));
      return jsonEncode(items.map((item) => item.toJson()).toList());
    });
  }

  /// Retorna todas as questões do Caderno de Erros.
  Future<List<ErrorQuestion>> getErrorQuestions({
    bool includeMastered = false,
  }) async {
    try {
      final rawJson = await _storage.getCacheValue(_kErrorNotebookStorageKey);
      if (rawJson == null || rawJson.trim().isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(rawJson);
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(ErrorQuestion.fromJson)
          .toList();

      if (!includeMastered) {
        return items.where((q) => !q.isMastered).toList();
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Registra uma lista de respostas incorretas vindas de uma sessão de quiz.
  Future<void> recordWrongQuestions({
    required List<QuestionAnswer> wrongAnswers,
    required String topic,
    String? sessionId,
  }) async {
    if (wrongAnswers.isEmpty) return;

    await _update((existing) {
      final map = <String, ErrorQuestion>{
        for (final q in existing) q.id: q,
      };

      for (final answer in wrongAnswers) {
        if (answer.isCorrect) continue;

        final questionId = answer.question.id;
        final current = map[questionId];
        if (sessionId != null &&
            current?.failedSessionIds.contains(sessionId) == true) {
          continue;
        }
        final sessions = [
          ...?current?.failedSessionIds,
          if (sessionId != null) sessionId
        ];

        if (current != null) {
          map[questionId] = current.copyWith(
            timesFailed: current.timesFailed + 1,
            failedSessionIds: sessions,
            failedAt: DateTime.now(),
            consecutiveCorrect: 0,
            isMastered:
                false, // Errou de novo — zera sequência de acertos e desmarca domínio
          );
        } else {
          map[questionId] = ErrorQuestion(
            id: questionId,
            topic: topic.isNotEmpty ? topic : 'Geral',
            question: answer.question,
            failedAt: DateTime.now(),
            timesFailed: 1,
            failedSessionIds: sessions,
            consecutiveCorrect: 0,
            isMastered: false,
          );
        }
      }

      return map.values.toList();
    });
  }

  /// Registra acerto na revisão. Marca como Dominada apenas com 2 acertos consecutivos (Curva de Ebbinghaus).
  Future<void> markQuestionMastered(String questionId) async {
    await _update((existing) => existing.map((q) {
          if (q.id == questionId) {
            final newStreak = q.consecutiveCorrect + 1;
            return q.copyWith(
              consecutiveCorrect: newStreak,
              isMastered: newStreak >= 2,
            );
          }
          return q;
        }).toList());
  }

  /// Remove todas as questões que já foram dominadas do Caderno de Erros.
  Future<void> clearMastered() async {
    await _update((existing) => existing.where((q) => !q.isMastered).toList());
  }
}

final errorNotebookRepositoryProvider = Provider<ErrorNotebookRepository>(
  (ref) => ErrorNotebookRepository(),
);
