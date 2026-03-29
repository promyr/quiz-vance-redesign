import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_vance_flutter/features/profile/data/billing_repository.dart';
import 'package:quiz_vance_flutter/features/profile/domain/premium_entry_mode.dart';
import 'package:quiz_vance_flutter/features/profile/presentation/premium_screen.dart';

final _mojibakePattern = RegExp(
  '\\u00C3.|\\u00C2.|\\u00E2\\u20AC|\\u00F0\\u0178|\\u00EF\\u00B8|\\uFFFD',
);

void expectNoMojibake(String value) {
  expect(value, isNot(matches(_mojibakePattern)));
}

void main() {
  const freeStatus = BillingStatus(planCode: 'free', isPremium: false);
  const premiumStatus = BillingStatus(
    planCode: 'premium_30',
    isPremium: true,
    premiumUntil: '2026-04-30T00:00:00Z',
  );
  const freePlan = BillingPlan(
    code: 'free',
    name: 'Gratis',
    priceCents: 0,
    currency: 'BRL',
    features: [],
  );
  const currentPremiumPlan = BillingPlan(
    code: 'premium_30',
    name: 'Premium Mensal',
    priceCents: 2990,
    currency: 'BRL',
    features: [],
  );
  const yearlyPlan = BillingPlan(
    code: 'premium_365',
    name: 'Premium Anual',
    priceCents: 19990,
    currency: 'BRL',
    features: [],
  );

  test('premiumEntryModeFromQuery reconhece manage e fallback subscribe', () {
    expect(
      premiumEntryModeFromQuery('manage'),
      equals(PremiumEntryMode.manage),
    );
    expect(
      premiumEntryModeFromQuery('subscribe'),
      equals(PremiumEntryMode.subscribe),
    );
    expect(
      premiumEntryModeFromQuery('desconhecido'),
      equals(PremiumEntryMode.subscribe),
    );
    expect(premiumEntryModeFromQuery(null), equals(PremiumEntryMode.subscribe));
  });

  test('premiumRouteForEntry gera rotas distintas', () {
    expect(
      premiumRouteForEntry(PremiumEntryMode.manage),
      equals('/premium?entry=manage'),
    );
    expect(
      premiumRouteForEntry(PremiumEntryMode.subscribe),
      equals('/premium?entry=subscribe'),
    );
  });

  test('buildPremiumPlanAction marca o plano atual como indisponivel', () {
    final action = buildPremiumPlanAction(
      plan: currentPremiumPlan,
      status: premiumStatus,
    );

    expect(action, isNotNull);
    expect(action!.label, equals('Plano atual'));
    expect(action.enabled, isFalse);
  });

  test('buildPremiumPlanAction usa Assinar agora para usuario free', () {
    final action = buildPremiumPlanAction(
      plan: currentPremiumPlan,
      status: freeStatus,
    );

    expect(action, isNotNull);
    expect(action!.label, equals('Assinar agora'));
    expect(action.enabled, isTrue);
  });

  test('buildPremiumPlanAction usa Trocar plano para premium em outro plano',
      () {
    final action = buildPremiumPlanAction(
      plan: yearlyPlan,
      status: premiumStatus,
    );

    expect(action, isNotNull);
    expect(action!.label, equals('Trocar plano'));
    expect(action.enabled, isTrue);
  });

  test('orderBillingPlans prioriza plano atual em modo manage', () {
    final ordered = orderBillingPlans(
      plans: const [freePlan, yearlyPlan, currentPremiumPlan],
      status: premiumStatus,
      entryMode: PremiumEntryMode.manage,
    );

    expect(ordered.first.code, equals('premium_30'));
  });

  test('orderBillingPlans prioriza planos pagos em modo subscribe', () {
    final ordered = orderBillingPlans(
      plans: const [freePlan, currentPremiumPlan],
      status: freeStatus,
      entryMode: PremiumEntryMode.subscribe,
    );

    expect(ordered.first.code, equals('premium_30'));
    expect(ordered.last.code, equals('free'));
  });

  test('visibleBillingPlans remove plano atual no modo manage', () {
    final visible = visibleBillingPlans(
      orderedPlans: const [currentPremiumPlan, yearlyPlan, freePlan],
      status: premiumStatus,
      entryMode: PremiumEntryMode.manage,
    );

    expect(visible.map((plan) => plan.code), isNot(contains('premium_30')));
    expect(visible.map((plan) => plan.code), contains('premium_365'));
  });

  test('visibleBillingPlans preserva comparacao completa no modo subscribe',
      () {
    final visible = visibleBillingPlans(
      orderedPlans: const [currentPremiumPlan, yearlyPlan, freePlan],
      status: premiumStatus,
      entryMode: PremiumEntryMode.subscribe,
    );

    expect(visible.map((plan) => plan.code), contains('premium_30'));
    expect(visible.length, equals(3));
  });

  test('buildPremiumHeroContent gera copy limpa em manage', () {
    final hero = buildPremiumHeroContent(
      entryMode: PremiumEntryMode.manage,
      status: premiumStatus,
      currentPlan: currentPremiumPlan,
      formattedPremiumUntil: '30/04/2026',
    );

    expect(hero.title, equals('Plano atual: Premium Mensal'));
    expect(hero.badgeLabel, equals('Modo gerenciamento'));
    expectNoMojibake(hero.title);
    expectNoMojibake(hero.subtitle);
    expectNoMojibake(hero.badgeLabel);
  });

  test('buildPremiumHeroContent gera copy limpa em subscribe', () {
    final hero = buildPremiumHeroContent(
      entryMode: PremiumEntryMode.subscribe,
      status: freeStatus,
      currentPlan: freePlan,
    );

    expect(hero.title, equals('Assine o Quiz Vance Premium'));
    expect(hero.badgeLabel, equals('Modo assinatura'));
    expectNoMojibake(hero.title);
    expectNoMojibake(hero.subtitle);
    expectNoMojibake(hero.badgeLabel);
  });
}
