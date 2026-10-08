import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/home/presentation/home_screen.dart';
import 'package:quiz_vance_flutter/features/profile/data/billing_repository.dart';
import 'package:quiz_vance_flutter/shared/widgets/bento_tile.dart';
import 'package:quiz_vance_flutter/shared/widgets/adaptive_hero_card.dart';
import 'package:quiz_vance_flutter/shared/widgets/streak_badge.dart';

void main() {
  testWidgets('hero remains readable with enlarged text on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data:
            MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.6)),
        child: child!,
      ),
      home: const Scaffold(
          body: SingleChildScrollView(
        child: AdaptiveHeroCard(firstName: 'Estudante', streak: 100),
      )),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('cards compactos nao estouram em celular estreito',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 120,
                height: 170,
                child: BentoTile(
                  title: 'Caderno de Erros',
                  subtitle: 'Revisao das questoes',
                  icon: Icons.style_rounded,
                  badgeText: 'MEMORIA',
                ),
              ),
              SizedBox(
                width: 76,
                child: StreakBadge(streak: 12, compact: true),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test(
      'preparePremiumUpsell aborta sem consultar billing quando frequencia bloqueia',
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
