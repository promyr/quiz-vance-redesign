import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/study_plan/data/study_plan_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late StudyPlanRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    apiClient = _MockApiClient();
    dio = _MockDio();
    repository = StudyPlanRepository(apiClient);

    when(() => apiClient.dio).thenReturn(dio);
  });

  test('generatePlan preserves backend validation detail', () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
          statusCode: 422,
          data: {
            'detail': [
              {
                'loc': ['body', 'goal'],
                'msg': 'Field required',
              },
            ],
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generatePlan(
        objetivo: 'TRT',
        tempoDiario: 60,
      ),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('goal: Field required'),
        ),
      ),
    );
  });

  test('generatePlan throws remote service exception on server failure',
      () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
        response: Response(
          requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
          statusCode: 500,
          data: {'detail': 'erro interno'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generatePlan(
        objetivo: 'TRT',
        tempoDiario: 60,
      ),
      throwsA(isA<RemoteServiceException>()),
    );
  });

  test('generatePlan forwards selected provider to backend', () async {
    when(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.studyPlanGenerate),
        data: {
          'semanas': [
            {
              'semana': 1,
              'foco': 'TRT',
              'tarefas': ['Revisar teoria'],
            },
          ],
        },
      ),
    );

    await repository.generatePlan(
      objetivo: 'TRT',
      tempoDiario: 60,
      aiProvider: 'groq',
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.studyPlanGenerate,
        data: captureAny(named: 'data'),
      ),
    ).captured.last as Map<String, dynamic>;

    expect(captured['provider'], 'groq');
  });
}
