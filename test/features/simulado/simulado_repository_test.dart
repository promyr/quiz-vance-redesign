import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/simulado/data/simulado_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late SimuladoRepository repository;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    repository = SimuladoRepository(apiClient);

    when(() => apiClient.dio).thenReturn(dio);
  });

  test('generateExam forwards selected provider to backend', () async {
    when(
      () => dio.post(
        ApiEndpoints.simuladoGenerate,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.simuladoGenerate),
        data: {
          'questions': [
            {
              'id': '1',
              'question': 'Pergunta',
              'options': [
                {'id': 'a', 'text': 'A', 'is_correct': true},
                {'id': 'b', 'text': 'B', 'is_correct': false},
              ],
              'correct_option_id': 'a',
              'explanation': 'Explicacao',
              'difficulty': 'easy',
            },
          ],
        },
      ),
    );

    await repository.generateExam(
      aiProvider: 'openai',
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.simuladoGenerate,
        data: captureAny(named: 'data'),
      ),
    ).captured.single as Map<String, dynamic>;

    expect(captured['provider'], 'openai');
  });
}
