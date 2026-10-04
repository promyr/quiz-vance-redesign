import 'dart:async';
import 'package:dio/dio.dart';
import 'quiz_generation_metrics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/exceptions/provider_rate_limit_exception.dart';
import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../domain/question_model.dart';

class QuizRepository {
  const QuizRepository(this._client);
  final ApiClient _client;

  Future<List<Question>> generate({
    required String topic,
    required String difficulty,
    required int quantity,
    String? aiProvider,
    String? conteudo,
    String? documentName,
    int? documentId,
  }) async {
    final timer = Stopwatch()..start();
    final metrics = QuizGenerationMetrics();
    var generated = <Question>[];
    try {
      final response = await _client.dio.post(
        ApiEndpoints.quizGenerate,
        data: {
          'topic': topic,
          'difficulty': difficulty,
          'quantity': quantity,
          if (aiProvider != null) 'provider': aiProvider,
          if (conteudo != null) 'context': conteudo,
          if (documentName != null) 'document_name': documentName,
          if (documentId != null) 'document_id': documentId,
        },
      );
      final data = response.data;
      if (data == null || data is! Map) {
        throw const FormatException('resposta inválida');
      }
      final list = (data['questions'] as List<dynamic>?) ?? [];
      generated = list
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList();
      return generated;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(e.response?.data);

      if (statusCode == 429) {
        if (detail != null && isProviderRateLimitMessage(detail)) {
          throw ProviderRateLimitException(detail);
        }
        throw PremiumLimitException(
          detail ?? 'Limite diário atingido. Faça upgrade para Premium.',
        );
      }

      // 401/403: nao expoe mensagem interna (ex: token inválido)
      if (statusCode == 401 || statusCode == 403) {
        throw const RemoteServiceException(
          'Não foi possível gerar o quiz. Verifique sua conexão e tente novamente.',
        );
      }

      if (detail != null && statusCode >= 400 && statusCode < 500) {
        throw RemoteServiceException(detail);
      }

      throw buildRemoteServiceException(
        e,
        fallback: 'Não foi possível gerar o quiz agora. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor do quiz. Verifique sua conexão e tente novamente.',
      );
    } finally {
      timer.stop();
      unawaited(metrics.record(
          durationMs: timer.elapsedMilliseconds,
          success: generated.isNotEmpty,
          texts: generated.map((q) => q.text).toList()));
    }
  }

  Future<Map<String, dynamic>> submit({
    required String sessionId,
    required List<Map<String, dynamic>> answers,
    required Duration timeTaken,
    required int total,
    required int correct,
    required int xpEarned,
    String? topic,
  }) async {
    final response = await _client.dio.post(
      ApiEndpoints.quizSubmit,
      data: {
        'session_id': sessionId,
        'answers': answers,
        'time_taken_seconds': timeTaken.inSeconds,
        'total': total,
        'correct': correct,
        'xp_earned': xpEarned,
        if (topic != null && topic.isNotEmpty) 'topic': topic,
      },
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> clearSeenQuestions({String? topic}) async {
    await _client.dio.delete(
      ApiEndpoints.quizClearSeenQuestions,
      queryParameters: {
        if (topic != null && topic.isNotEmpty) 'topic': topic,
      },
    );
  }
}

final quizRepositoryProvider = Provider<QuizRepository>(
  (ref) => QuizRepository(ref.watch(apiClientProvider)),
);
