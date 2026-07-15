import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/account/data/account_deletion_repository.dart';

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

  test('envia DeleteAccountIn no DELETE /user/account', () async {
    when(
      () => dio.delete(
        ApiEndpoints.userAccount,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.userAccount),
        data: const {'ok': true},
      ),
    );

    await AccountDeletionRepository(apiClient).deleteAccount(
      const DeleteAccountRequest(
        currentPassword: 'senha-segura',
        confirmationText: 'EXCLUIR MINHA CONTA',
      ),
    );

    final body = verify(
      () => dio.delete(
        ApiEndpoints.userAccount,
        data: captureAny(named: 'data'),
      ),
    ).captured.single;
    expect(body, {
      'current_password': 'senha-segura',
      'confirmation_text': 'EXCLUIR MINHA CONTA',
    });
  });

  test('propaga detail do backend na exclusão', () async {
    final request = RequestOptions(path: ApiEndpoints.userAccount);
    when(
      () => dio.delete(
        ApiEndpoints.userAccount,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 400,
          data: const {'detail': 'Senha atual inválida'},
        ),
      ),
    );

    await expectLater(
      AccountDeletionRepository(apiClient).deleteAccount(
        const DeleteAccountRequest(
          currentPassword: 'incorreta',
          confirmationText: 'EXCLUIR MINHA CONTA',
        ),
      ),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'Senha atual inválida',
        ),
      ),
    );
  });
}
