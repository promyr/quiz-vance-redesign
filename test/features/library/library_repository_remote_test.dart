import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/library/data/library_repository.dart';
import 'package:quiz_vance_flutter/features/library/domain/library_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;
  late LibraryRepository repository;
  final file = LibraryFile(
    id: 1,
    nome: 'Biologia',
    categoria: 'Vestibular',
    conteudo: 'Resumo sobre celulas',
    criadoEm: DateTime(2026, 3, 24),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    apiClient = _MockApiClient();
    dio = _MockDio();
    repository = LibraryRepository(apiClient);

    when(() => apiClient.dio).thenReturn(dio);
  });

  test('generatePackage preserves backend validation detail', () async {
    when(
      () => dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions:
            RequestOptions(path: ApiEndpoints.libraryGeneratePackage),
        response: Response(
          requestOptions:
              RequestOptions(path: ApiEndpoints.libraryGeneratePackage),
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
      repository.generatePackage(file: file),
      throwsA(
        predicate<Object>(
          (error) => error.toString().contains('topic: Field required'),
        ),
      ),
    );
  });

  test('generatePackage no longer falls back silently on server failure',
      () async {
    when(
      () => dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions:
            RequestOptions(path: ApiEndpoints.libraryGeneratePackage),
        response: Response(
          requestOptions:
              RequestOptions(path: ApiEndpoints.libraryGeneratePackage),
          statusCode: 500,
          data: {'detail': 'erro interno'},
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    await expectLater(
      repository.generatePackage(file: file),
      throwsA(isA<RemoteServiceException>()),
    );
  });

  test('generatePackage forwards selected provider to backend', () async {
    when(
      () => dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions:
            RequestOptions(path: ApiEndpoints.libraryGeneratePackage),
        data: {
          'titulo': 'Pacote',
          'resumo_curto': 'Resumo',
          'topicos_principais': const ['A'],
          'sugestoes_flashcards': const [],
          'sugestoes_questoes': const [],
          'checklist_de_estudo': const ['Ler'],
        },
      ),
    );

    await repository.generatePackage(
      file: file,
      aiProvider: 'gemini',
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: captureAny(named: 'data'),
      ),
    ).captured.last as Map<String, dynamic>;

    expect(captured['provider'], 'gemini');
  });

  test('generatePackage filters metadata flashcards from backend payload',
      () async {
    final fileWithContent = LibraryFile(
      id: 2,
      nome: 'Comportamento Organizacional',
      categoria: 'Administracao',
      conteudo: '''
Introducao ao comportamento organizacional.
O comportamento humano nas empresas envolve motivacao, lideranca e cultura.
Esses fatores afetam desempenho, clima e tomada de decisao.
Lideres moldam normas, incentivos e colaboracao entre equipes.
      ''',
      criadoEm: DateTime(2026, 3, 24),
    );

    when(
      () => dio.post(
        ApiEndpoints.libraryGeneratePackage,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions:
            RequestOptions(path: ApiEndpoints.libraryGeneratePackage),
        data: {
          'titulo': 'Comportamento Organizacional',
          'resumo_curto': 'Resumo',
          'topicos_principais': const [
            'Motivacao',
            'ISBN e ficha catalografica'
          ],
          'sugestoes_flashcards': const [
            {
              'front': 'O que e motivacao nas empresas?',
              'back': 'Fatores que impulsionam o comportamento no trabalho.',
            },
            {
              'front': 'Qual e o ISBN do material?',
              'back': '978-85-0000-000-0',
            },
          ],
          'sugestoes_questoes': const [],
          'checklist_de_estudo': const ['Revisar cultura', 'Consultar ISBN'],
        },
      ),
    );

    final package = await repository.generatePackage(file: fileWithContent);

    expect(package.flashcards, hasLength(1));
    expect(package.flashcards.first['front'], contains('motivacao'));
    expect(package.topicosPrincipais, ['Motivacao']);
    expect(package.checklistEstudo, ['Revisar cultura']);
  });
}
