import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quiz_vance_flutter/core/observability/app_observability.dart';
import 'package:quiz_vance_flutter/features/auth/domain/auth_state.dart';
import 'package:quiz_vance_flutter/features/profile/application/premium_checkout_coordinator.dart';
import 'package:quiz_vance_flutter/features/profile/data/billing_repository.dart';

class _MockBillingRepository extends Mock implements BillingRepository {}

void main() {
  late _MockBillingRepository repository;
  late PremiumCheckoutCoordinator coordinator;

  const monthlyPlan = BillingPlan(
    code: 'premium_30',
    name: 'Premium Mensal',
    priceCents: 2990,
    currency: 'BRL',
    features: [],
  );

  setUp(() {
    repository = _MockBillingRepository();
    coordinator = PremiumCheckoutCoordinator(
      repository,
      observability: AppObservability(maxEntries: 20),
    );
  });

  test('bloqueia checkout sem sessao valida', () async {
    await expectLater(
      coordinator.startCheckout(
        authState: const AuthState(isAuthenticated: false),
        plan: monthlyPlan,
      ),
      throwsA(isA<PremiumCheckoutException>()),
    );
  });

  test('monta checkout com fallback de nome', () async {
    when(
      () => repository.startCheckout(
        userId: any(named: 'userId'),
        name: any(named: 'name'),
        email: any(named: 'email'),
        planCode: any(named: 'planCode'),
        provider: any(named: 'provider'),
      ),
    ).thenAnswer(
      (_) async => const CheckoutStartResult(
        checkoutUrl: 'https://checkout.quizvance.app/session/1',
        checkoutId: 'chk_1',
      ),
    );

    final url = await coordinator.startCheckout(
      authState: const AuthState(
        isAuthenticated: true,
        userId: '123',
        name: '   ',
        email: 'belchior@quizvance.app',
      ),
      plan: monthlyPlan,
    );

    expect(url, equals('https://checkout.quizvance.app/session/1'));
    verify(
      () => repository.startCheckout(
        userId: 123,
        name: 'Usuario',
        email: 'belchior@quizvance.app',
        planCode: 'premium_30',
        provider: any(named: 'provider'),
      ),
    ).called(1);
  });

  test('bloqueia checkout quando user_id nao e numerico', () async {
    await expectLater(
      coordinator.startCheckout(
        authState: const AuthState(
          isAuthenticated: true,
          userId: 'user-uuid-123',
          email: 'belchior@quizvance.app',
        ),
        plan: monthlyPlan,
      ),
      throwsA(
        isA<PremiumCheckoutException>().having(
          (error) => error.message,
          'message',
          contains('sessao valida'),
        ),
      ),
    );
    verifyNever(
      () => repository.startCheckout(
        userId: any(named: 'userId'),
        name: any(named: 'name'),
        email: any(named: 'email'),
        planCode: any(named: 'planCode'),
        provider: any(named: 'provider'),
      ),
    );
  });

  test('falha quando backend nao devolve checkout_url', () async {
    when(
      () => repository.startCheckout(
        userId: any(named: 'userId'),
        name: any(named: 'name'),
        email: any(named: 'email'),
        planCode: any(named: 'planCode'),
        provider: any(named: 'provider'),
      ),
    ).thenAnswer(
      (_) async => const CheckoutStartResult(
        checkoutUrl: '',
        checkoutId: 'chk_2',
      ),
    );

    await expectLater(
      coordinator.startCheckout(
        authState: const AuthState(
          isAuthenticated: true,
          userId: '2',
          name: 'Belchior',
          email: 'belchior@quizvance.app',
        ),
        plan: monthlyPlan,
      ),
      throwsA(isA<PremiumCheckoutException>()),
    );
  });

  for (final invalidUrl in [
    'http://www.mercadopago.com.br/checkout/1',
    'https://mercadopago.com.br.attacker.test/checkout/1',
    'https://evil.test/checkout/1',
    'not-a-url',
  ]) {
    test('bloqueia URL de checkout insegura: $invalidUrl', () async {
      when(
        () => repository.startCheckout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          email: any(named: 'email'),
          planCode: any(named: 'planCode'),
          provider: any(named: 'provider'),
        ),
      ).thenAnswer(
        (_) async => CheckoutStartResult(
          checkoutUrl: invalidUrl,
          checkoutId: 'chk_invalid',
        ),
      );

      await expectLater(
        coordinator.startCheckout(
          authState: const AuthState(
            isAuthenticated: true,
            userId: '123',
            name: 'Belchior',
            email: 'belchior@quizvance.app',
          ),
          plan: monthlyPlan,
        ),
        throwsA(
          isA<PremiumCheckoutException>().having(
            (error) => error.message,
            'message',
            contains('URL segura'),
          ),
        ),
      );
    });
  }

  for (final validUrl in [
    'https://www.mercadopago.com.br/checkout/v1/redirect',
    'https://sandbox.mercadopago.com.br/checkout/v1/redirect',
    'https://checkout.quizvance.app/session/1',
  ]) {
    test('aceita host de checkout permitido: $validUrl', () async {
      when(
        () => repository.startCheckout(
          userId: any(named: 'userId'),
          name: any(named: 'name'),
          email: any(named: 'email'),
          planCode: any(named: 'planCode'),
          provider: any(named: 'provider'),
        ),
      ).thenAnswer(
        (_) async => CheckoutStartResult(
          checkoutUrl: validUrl,
          checkoutId: 'chk_valid',
        ),
      );

      final result = await coordinator.startCheckout(
        authState: const AuthState(
          isAuthenticated: true,
          userId: '123',
          name: 'Belchior',
          email: 'belchior@quizvance.app',
        ),
        plan: monthlyPlan,
      );

      expect(result, validUrl);
    });
  }
}
