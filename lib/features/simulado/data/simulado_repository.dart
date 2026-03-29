import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../../quiz/domain/question_model.dart';

class SimuladoRepository {
  const SimuladoRepository(this._client);

  final ApiClient _client;

  Future<List<Question>> generateExam({
    int quantity = 30,
    String difficulty = 'mixed',
    String? topic,
    String? conteudo,
    String? aiProvider,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.simuladoGenerate,
        data: {
          'quantity': quantity,
          'difficulty': difficulty,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
          if (conteudo != null) 'context': conteudo,
          if (aiProvider != null && aiProvider.isNotEmpty)
            'provider': aiProvider,
        },
      );

      return (response.data['questions'] as List<dynamic>)
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
        throw RemoteServiceException('Erro $statusCode ao gerar simulado');
      }

      throw buildRemoteServiceException(
        e,
        fallback: 'Não foi possível gerar o simulado agora. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor do simulado. Verifique sua conexão e tente novamente.',
      );
    }
  }

  Future<void> submitResult(Map<String, dynamic> payload) async {
    try {
      await _client.dio.post(ApiEndpoints.simuladoSubmit, data: payload);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(e.response?.data);

      if (detail != null) {
        if (statusCode >= 400 && statusCode < 500) {
          throw RemoteServiceException(detail);
        }
        throw RemoteServiceException(detail);
      }

      if (statusCode >= 400 && statusCode < 500) {
        throw RemoteServiceException('Erro $statusCode ao salvar resultado do simulado');
      }

      rethrow;
    }
  }
}

final simuladoRepositoryProvider = Provider<SimuladoRepository>(
  (ref) => SimuladoRepository(ref.watch(apiClientProvider)),
);
