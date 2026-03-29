import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_error_message.dart';
import '../domain/open_quiz_model.dart';

class OpenQuizRepository {
  const OpenQuizRepository(this._client);

  final ApiClient _client;

  Future<OpenQuestion> generateQuestion({
    required String tema,
    String dificuldade = 'intermediario',
    String? conteudo,
    String? aiProvider,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.quizOpenGenerate,
        data: {
          'tema': tema,
          'dificuldade': dificuldade,
          if (conteudo != null) 'contexto_material': conteudo,
          if (aiProvider != null && aiProvider.isNotEmpty)
            'provider': aiProvider,
        },
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('resposta invalida');
      }
      return OpenQuestion.fromJson(raw);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(error.response?.data);

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
          'Usuarios free podem gerar 1 questao dissertativa por semana. Faca upgrade para Premium.',
        );
      }

      if (statusCode >= 400 && statusCode < 500) {
        throw RemoteServiceException(
          'Erro $statusCode ao gerar questao dissertativa',
        );
      }

      throw buildRemoteServiceException(
        error,
        fallback:
            'Nao foi possivel gerar a questao dissertativa agora. Tente novamente.',
        connectivityFallback:
            'Nao foi possivel conectar ao servidor das questoes dissertativas. Verifique sua conexao e tente novamente.',
      );
    }
  }

  Future<OpenGrade> gradeAnswer({
    required OpenQuestion question,
    required String answer,
  }) async {
    try {
      final response = await _client.dio.post(
        ApiEndpoints.quizOpenGrade,
        data: {
          'pergunta': question.pergunta,
          'resposta_esperada': question.respostaEsperada,
          'resposta_aluno': answer,
        },
      );
      final raw = response.data;
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('resposta invalida');
      }
      return OpenGrade.fromJson(raw);
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode ?? 0;
      final detail = extractApiErrorMessage(error.response?.data);

      if (detail != null) {
        if (statusCode >= 400 && statusCode < 500) {
          throw RemoteServiceException(detail);
        }
        throw RemoteServiceException(detail);
      }

      if (statusCode >= 400 && statusCode < 500) {
        throw RemoteServiceException('Erro $statusCode ao corrigir resposta');
      }

      throw buildRemoteServiceException(
        error,
        fallback:
            'Não foi possível corrigir a resposta agora. Tente novamente.',
        connectivityFallback:
            'Não foi possível conectar ao servidor de correção. Verifique sua conexão e tente novamente.',
      );
    }
  }
}

final openQuizRepositoryProvider = Provider<OpenQuizRepository>(
  (ref) => OpenQuizRepository(ref.watch(apiClientProvider)),
);