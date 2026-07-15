import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/exceptions/remote_service_exception.dart';
import 'package:quiz_vance_flutter/core/network/api_client.dart';
import 'package:quiz_vance_flutter/core/network/api_endpoints.dart';
import 'package:quiz_vance_flutter/features/profile/data/billing_repository.dart';

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

  test('envia o body exato de CheckoutStartIn', () async {
    when(
      () => dio.post(
        ApiEndpoints.billingCheckoutStart,
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ApiEndpoints.billingCheckoutStart),
        data: {
          'checkout_url': 'https://checkout.test',
          'checkout_id': 'chk_1',
        },
      ),
    );

    final repository = BillingRepository(apiClient);
    await repository.startCheckout(
      userId: 42,
      name: 'Bel Test',
      email: 'bel@test.com',
      planCode: 'premium_365',
    );

    final captured = verify(
      () => dio.post(
        ApiEndpoints.billingCheckoutStart,
        data: captureAny(named: 'data'),
      ),
    ).captured.single as Map<String, dynamic>;

    expect(captured, {
      'user_id': 42,
      'plan_code': 'premium_365',
      'provider': 'mercadopago',
      'name': 'Bel Test',
      'email_id': 'bel@test.com',
    });
  });

  test('propaga detail do backend ao carregar planos', () async {
    when(() => dio.get(ApiEndpoints.billingPlans)).thenThrow(
      _dioException(
        path: ApiEndpoints.billingPlans,
        data: {'detail': 'Billing indisponivel agora'},
      ),
    );

    final repository = BillingRepository(apiClient);

    await expectLater(
      repository.getPlans(),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'Billing indisponivel agora',
        ),
      ),
    );
  });

  test('usa fallback amigavel quando status falha sem detail', () async {
    when(() => dio.get(ApiEndpoints.billingStatus)).thenThrow(
      _dioException(
        path: ApiEndpoints.billingStatus,
        data: {'unexpected': true},
      ),
    );

    final repository = BillingRepository(apiClient);

    await expectLater(
      repository.getStatus(),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'Não foi possível verificar o status do plano.',
        ),
      ),
    );
  });

  test('propaga erros de validacao do checkout', () async {
    when(
      () => dio.post(
        ApiEndpoints.billingCheckoutStart,
        data: any(named: 'data'),
      ),
    ).thenThrow(
      _dioException(
        path: ApiEndpoints.billingCheckoutStart,
        data: {
          'detail': [
            {
              'loc': ['body', 'email'],
              'msg': 'Field required',
            },
          ],
        },
      ),
    );

    final repository = BillingRepository(apiClient);

    await expectLater(
      repository.startCheckout(
        userId: 42,
        name: 'Bel Test',
        email: 'bel@test.com',
      ),
      throwsA(
        isA<RemoteServiceException>().having(
          (error) => error.message,
          'message',
          'email: Field required',
        ),
      ),
    );
  });
}

DioException _dioException({
  required String path,
  required Object? data,
}) {
  final request = RequestOptions(path: path);
  return DioException(
    requestOptions: request,
    response: Response(
      requestOptions: request,
      data: data,
      statusCode: 400,
    ),
  );
}
