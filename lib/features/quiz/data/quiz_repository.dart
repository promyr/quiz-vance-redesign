import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
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
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.quizGenerate,
        data: {
          'topic': topic,
          'difficulty': difficulty,
          'quantity': quantity,
          if (aiProvider != null) 'provider': aiProvider,
          if (conteudo != null) 'context': conteudo,
        },
      );
      final data = response.data;
      if (data == null || data is! Map) {
        throw const FormatException('resposta inválida');
      }
      final list = (data['questions'] as List<dynamic>?) ?? [];
      return list
          .map((e) => Question.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(e.response?.data);

      if (detail != null) {
        if (statusCode == 429) {
          throw PremiumLimitException(detail);
        }
        if (statusCode >= 400 && statusCode < 500) {
          throw RemoteServiceException(detail);
        }
        throw RemoteServiceException(detail);
      }

      if (statusCode == 429) {
        throw PremiumLimitException(
          'Limite diário atingido. Faça upgrade para Premium.',
        );
      }

      if (statusCode >= 400 && statusCode < 500) {
        throw RemoteServiceException('Erro $statusCode ao gerar quiz');
      }

      throw buildRemoteServiceException(
        e,
        fallback: 'Não foi possível gerar o quiz agora. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor do quiz. Verifique sua conexão e tente novamente.',
      );
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
