import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/premium_limit_exception.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/open_quiz/data/open_quiz_repository.dart';
import 'package:quiz_vance_flutter/features/open_quiz/domain/open_quiz_model.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late OpenQuizRepository repository;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    repository = OpenQuizRepository(apiClient);

    when(() => apiClient.dio).thenReturn(dio);
  });

  test('generateQuestion preserves backend validation detail', () async {
    when(
      () => dio.post(
        ApiEndpoints.quizOpenGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGenerate),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'tema'],
                'msg': 'Field required',
              },
            ],
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generateQuestion(tema: 'Historia'),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('tema: Field required'),
        ),
      ),
    );
  });

  test('gradeAnswer throws remote service exception on server failure',
      () async {
    when(
      () => dio.post(
        ApiEndpoints.quizOpenGrade,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGrade),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGrade),
          statusCode: 500,
          data: {'detail': 'erro interno'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.gradeAnswer(
        question: const OpenQuestion(
          pergunta: 'Pergunta',
          contexto: 'Contexto',
          respostaEsperada: 'Resposta',
        ),
        answer: 'Minha resposta',
      ),
      throwsA(isA<RemoteServiceException>()),
    );
  });

  test('generateQuestion forwards selected provider to backend', () async {
    when(
      () => dio.post(
        ApiEndpoints.quizOpenGenerate,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGenerate),
        data: const {
          'pergunta': 'Pergunta',
          'contexto': 'Contexto',
          'resposta_esperada': 'Resposta',
        },
      ),
    );

    await repository.generateQuestion(
      tema: 'Historia',
      aiProvider: 'openai',
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.quizOpenGenerate,
        data: captureAny(named: 'data'),
      ),
    ).captured.last as Map<String, dynamic>;

    expect(captured['provider'], 'openai');
  });

  test('generateQuestion maps 429 to premium limit exception', () async {
    when(
      () => dio.post(
        ApiEndpoints.quizOpenGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.quizOpenGenerate),
          statusCode: 429,
          data: {
            'detail':
                'Usuários free podem gerar 1 questão dissertativa por semana.',
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generateQuestion(tema: 'Historia'),
      throwsA(
        predicate<Object>(
          (error) =>
              error is PremiumLimitException &&
              error.message.contains('1 questão dissertativa por semana'),
        ),
      ),
    );
  });
}
