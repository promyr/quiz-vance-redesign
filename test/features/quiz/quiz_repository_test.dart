import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/premium_limit_exception.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/quiz/data/quiz_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late QuizRepository repository;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    repository = QuizRepository(apiClient);

    when(() => apiClient.dio).thenReturn(dio);
  });

  test('generate preserves backend validation message from detail list',
      () async {
    when(
      () => dio.post(
        ApiEndpoints.quizGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.quizGenerate),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'topic'],
                'msg': 'Field required',
              },
            ],
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generate(
        topic: 'Historia',
        difficulty: 'medium',
        quantity: 10,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('topic: Field required'),
        ),
      ),
    );
  });

  test('generate throws premium exception with backend detail', () async {
    when(
      () => dio.post(
        ApiEndpoints.quizGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.quizGenerate),
          statusCode: 429,
          data: {'detail': 'Limite diario atingido.'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generate(
        topic: 'Historia',
        difficulty: 'medium',
        quantity: 10,
      ),
      throwsA(
        isA<PremiumLimitException>().having(
          (error) => error.message,
          'message',
          'Limite diario atingido.',
        ),
      ),
    );
  });

  test('generate preserves backend detail on server errors', () async {
    when(
      () => dio.post(
        ApiEndpoints.quizGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.quizGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.quizGenerate),
          statusCode: 500,
          data: {'detail': 'erro interno'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generate(
        topic: 'Historia',
        difficulty: 'medium',
        quantity: 10,
      ),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'erro interno',
        ),
      ),
    );
  });
}
