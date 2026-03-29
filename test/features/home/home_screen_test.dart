import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/home/presentation/home_screen.dart';
import 'package:quiz_vance_flutter/features/profile/data/billing_repository.dart';

void main() {
  test('preparePremiumUpsell aborta sem consultar billing quando frequencia bloqueia',
      () async {
    var fetchCalled = false;
    var markCalled = false;

    final shouldShow = await preparePremiumUpsell(
      shouldShowUpsell: () async => false,
      fetchBillingStatus: () async {
        fetchCalled = true;
        return const BillingStatus(planCode: 'free', isPremium: false);
      },
      markUpsellShown: () async {
        markCalled = true;
      },
    );

    expect(shouldShow, isFalse);
    expect(fetchCalled, isFalse);
    expect(markCalled, isFalse);
  });

  test('preparePremiumUpsell nao marca exibicao para usuario premium',
      () async {
    var markCalled = false;

    final shouldShow = await preparePremiumUpsell(
      shouldShowUpsell: () async => true,
      fetchBillingStatus: () async =>
          const BillingStatus(planCode: 'premium_30', isPremium: true),
      markUpsellShown: () async {
        markCalled = true;
      },
    );

    expect(shouldShow, isFalse);
    expect(markCalled, isFalse);
  });

  test('preparePremiumUpsell falha fechado quando billing oscila', () async {
    var markCalled = false;

    final shouldShow = await preparePremiumUpsell(
      shouldShowUpsell: () async => true,
      fetchBillingStatus: () async {
        throw Exception('billing offline');
      },
      markUpsellShown: () async {
        markCalled = true;
      },
    );

    expect(shouldShow, isFalse);
    expect(markCalled, isFalse);
  });

  test('preparePremiumUpsell libera e marca exibicao para usuario free',
      () async {
    var markCalled = false;

    final shouldShow = await preparePremiumUpsell(
      shouldShowUpsell: () async => true,
      fetchBillingStatus: () async =>
          const BillingStatus(planCode: 'free', isPremium: false),
      markUpsellShown: () async {
        markCalled = true;
      },
    );

    expect(shouldShow, isTrue);
    expect(markCalled, isTrue);
  });
}
