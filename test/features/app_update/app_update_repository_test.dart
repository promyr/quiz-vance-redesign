import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/app_update/data/app_update_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient apiClient;
  late _MockDio dio;

  setUp(() {
    apiClient = _MockApiClient();
    dio = _MockDio();
    when(() => apiClient.dio).thenReturn(dio);
  });

  test('consulta /app/update com platform e modela AppUpdateInfoOut', () async {
    when(
      () => dio.get(
        ApiEndpoints.appUpdate,
        queryParameters: {'platform': 'android'},
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.appUpdate),
        data: const {
          'ok': true,
          'platform': 'android',
          'latest_version': '2.1.0',
          'minimum_supported_version': '2.0.0',
          'download_url': 'https://quizvance.app/download/app.apk',
          'release_notes': 'Melhorias de estabilidade.',
          'published_at': '2026-07-15T12:00:00Z',
        },
      ),
    );

    final result = await AppUpdateRepository(apiClient).getUpdateInfo();

    expect(result.ok, isTrue);
    expect(result.platform, 'android');
    expect(result.latestVersion, '2.1.0');
    expect(result.minimumSupportedVersion, '2.0.0');
    expect(result.downloadUrl, 'https://quizvance.app/download/app.apk');
    expect(result.releaseNotes, 'Melhorias de estabilidade.');
    expect(result.publishedAt, DateTime.utc(2026, 7, 15, 12));
  });

  test('preserva campos opcionais nulos da resposta', () async {
    when(
      () => dio.get(
        ApiEndpoints.appUpdate,
        queryParameters: {'platform': 'ios'},
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.appUpdate),
        data: const {'ok': true, 'platform': 'ios'},
      ),
    );

    final result =
        await AppUpdateRepository(apiClient).getUpdateInfo(platform: 'ios');

    expect(result.latestVersion, isNull);
    expect(result.minimumSupportedVersion, isNull);
    expect(result.downloadUrl, isNull);
    expect(result.releaseNotes, isNull);
    expect(result.publishedAt, isNull);
  });

  test('converte falha remota em mensagem de update', () async {
    final request = RequestOptions(path: ApiEndpoints.appUpdate);
    when(
      () => dio.get(
        ApiEndpoints.appUpdate,
        queryParameters: {'platform': 'android'},
      ),
    ).thenThrow(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 503,
          data: const {'detail': 'Canal de atualização indisponível'},
        ),
      ),
    );

    await expectLater(
      AppUpdateRepository(apiClient).getUpdateInfo(),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'Canal de atualização indisponível',
        ),
      ),
    );
  });
}
