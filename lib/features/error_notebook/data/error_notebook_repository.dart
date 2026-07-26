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
  }) async {
    if (wrongAnswers.isEmpty) return;

    final existing = await getErrorQuestions(includeMastered: true);
    final map = <String, ErrorQuestion>{
      for (final q in existing) q.id: q,
    };

    for (final answer in wrongAnswers) {
      if (answer.isCorrect) continue;

      final questionId = answer.question.id;
      final current = map[questionId];

      if (current != null) {
        map[questionId] = current.copyWith(
          timesFailed: current.timesFailed + 1,
          failedAt: DateTime.now(),
          isMastered: false, // Errou de novo — desmarca domínio
        );
      } else {
        map[questionId] = ErrorQuestion(
          id: questionId,
          topic: topic.isNotEmpty ? topic : 'Geral',
          question: answer.question,
          failedAt: DateTime.now(),
          timesFailed: 1,
          isMastered: false,
        );
      }
    }

    final updatedList = map.values.toList();
    final jsonString = jsonEncode(updatedList.map((e) => e.toJson()).toList());
    await _storage.setCacheValue(_kErrorNotebookStorageKey, jsonString);
  }

  /// Marca uma questão como "Dominada" após ser respondida corretamente durante a revisão.
  Future<void> markQuestionMastered(String questionId) async {
    final existing = await getErrorQuestions(includeMastered: true);
    final updatedList = existing.map((q) {
      if (q.id == questionId) {
        return q.copyWith(isMastered: true);
      }
      return q;
    }).toList();

    final jsonString = jsonEncode(updatedList.map((e) => e.toJson()).toList());
    await _storage.setCacheValue(_kErrorNotebookStorageKey, jsonString);
  }

  /// Remove todas as questões que já foram dominadas do Caderno de Erros.
  Future<void> clearMastered() async {
    final existing = await getErrorQuestions(includeMastered: true);
    final remaining = existing.where((q) => !q.isMastered).toList();
    final jsonString = jsonEncode(remaining.map((e) => e.toJson()).toList());
    await _storage.setCacheValue(_kErrorNotebookStorageKey, jsonString);
  }
}

final errorNotebookRepositoryProvider = Provider<ErrorNotebookRepository>(
  (ref) => ErrorNotebookRepository(),
);
