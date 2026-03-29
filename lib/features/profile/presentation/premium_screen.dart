import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../application/premium_checkout_coordinator.dart';
import '../data/billing_repository.dart';
import '../domain/premium_entry_mode.dart';

class PremiumHeroContent {
  const PremiumHeroContent({
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.gradient,
  });

  final String title;
  final String subtitle;
  final String badgeLabel;
  final Gradient gradient;
}

class PremiumPlanAction {
  const PremiumPlanAction({
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;
}

PremiumHeroContent buildPremiumHeroContent({
  required PremiumEntryMode entryMode,
  required BillingStatus status,
  BillingPlan? currentPlan,
  String? formattedPremiumUntil,
}) {
  final currentPlanName = currentPlan?.name ?? 'Premium';

  if (entryMode == PremiumEntryMode.manage) {
    if (status.isPremium) {
      final untilText = formattedPremiumUntil == null
          ? 'Seu acesso premium esta ativo.'
          : 'Seu acesso premium esta ativo ate $formattedPremiumUntil.';

      return PremiumHeroContent(
        title: 'Plano atual: $currentPlanName',
        subtitle:
            '$untilText Esta tela é focada em status, renovação e troca de plano.',
        badgeLabel: 'Modo gerenciamento',
        gradient: AppColors.successGradient,
      );
    }

    return const PremiumHeroContent(
      title: 'Você está no plano grátis',
      subtitle:
          'Esta tela mostra seu status atual. Quando quiser comprar, entre pelo atalho Assinar Premium.',
      badgeLabel: 'Modo gerenciamento',
      gradient: AppColors.primaryGradient,
    );
  }

  if (status.isPremium) {
    return const PremiumHeroContent(
      title: 'Troque ou renove seu Premium',
      subtitle:
          'Esta tela é focada em compra. Compare os planos pagos e escolha a melhor opção para continuar.',
      badgeLabel: 'Modo assinatura',
      gradient: AppColors.successGradient,
    );
  }

  return const PremiumHeroContent(
    title: 'Assine o Quiz Vance Premium',
    subtitle:
        'Esta tela é focada em compra. Escolha um plano pago para liberar quizzes, simulados, flashcards e plano de estudo.',
    badgeLabel: 'Modo assinatura',
    gradient: AppColors.primaryGradient,
  );
}

PremiumPlanAction? buildPremiumPlanAction({
  required BillingPlan plan,
  required BillingStatus status,
}) {
  final isCurrentPlan = status.planCode == plan.code;
  final isPaidPlan = plan.priceCents > 0;

  if (isCurrentPlan) {
    return const PremiumPlanAction(
      label: 'Plano atual',
      enabled: false,
    );
  }

  if (!isPaidPlan) {
    return null;
  }

  return PremiumPlanAction(
    label: status.isPremium ? 'Trocar plano' : 'Assinar agora',
    enabled: true,
  );
}

List<BillingPlan> orderBillingPlans({
  required List<BillingPlan> plans,
  required BillingStatus status,
  required PremiumEntryMode entryMode,
}) {
  final sorted = [...plans];

  int priority(BillingPlan plan) {
    final isCurrentPlan = plan.code == status.planCode;
    final isPaidPlan = plan.priceCents > 0;

    if (entryMode == PremiumEntryMode.manage) {
      if (isCurrentPlan) return 0;
      if (isPaidPlan) return 1;
      return 2;
    }

    if (isPaidPlan) return 0;
    if (isCurrentPlan) return 1;
    return 2;
  }

  sorted.sort((left, right) {
    final byPriority = priority(left).compareTo(priority(right));
    if (byPriority != 0) return byPriority;

    final byPrice = right.priceCents.compareTo(left.priceCents);
    if (byPrice != 0) return byPrice;

    return left.name.compareTo(right.name);
  });

  return sorted;
}

List<BillingPlan> visibleBillingPlans({
  required List<BillingPlan> orderedPlans,
  required BillingStatus status,
  required PremiumEntryMode entryMode,
}) {
  if (entryMode != PremiumEntryMode.manage) {
    return orderedPlans;
  }

  final filtered = orderedPlans
      .where((plan) => plan.code != status.planCode)
      .toList(growable: false);

  return filtered.isEmpty ? orderedPlans : filtered;
}

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({
    super.key,
    required this.entryMode,
  });

  final PremiumEntryMode entryMode;

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _startingCheckout = false;

  bool get _isManageMode => widget.entryMode == PremiumEntryMode.manage;

  Future<void> _refreshBilling() async {
    ref.invalidate(billingStatusProvider);
    ref.invalidate(billingPlansProvider);
    await Future.wait([
      ref.read(billingStatusProvider.future),
      ref.read(billingPlansProvider.future),
    ]);
  }

  Future<void> _startCheckout(BillingPlan plan) async {
    setState(() => _startingCheckout = true);
    try {
      final checkoutUrl =
          await ref.read(premiumCheckoutCoordinatorProvider).startCheckout(
                authState: ref.read(premiumCheckoutAuthStateProvider),
                plan: plan,
              );

      final launched = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw const RemoteServiceException(
          'Não foi possível abrir o checkout no dispositivo.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = userVisibleErrorMessage(
        error,
        fallback: 'Não foi possível iniciar o checkout. Tente novamente.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.accent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _startingCheckout = false);
      }
    }
  }

  String? _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  BillingPlan? _findCurrentPlan(List<BillingPlan> plans, BillingStatus status) {
    for (final plan in plans) {
      if (plan.code == status.planCode) return plan;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(billingStatusProvider);
    final plansAsync = ref.watch(billingPlansProvider);
    final status = statusAsync.valueOrNull;
    final plans = plansAsync.valueOrNull;
    final loadError = statusAsync.whenOrNull(error: (error, _) => error) ??
        plansAsync.whenOrNull(error: (error, _) => error);

    final isInitialLoading = (statusAsync.isLoading && status == null) ||
        (plansAsync.isLoading && plans == null);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  _BackButton(
                    onTap: () => context.canPop()
                        ? context.pop()
                        : context.go('/profile'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isManageMode ? 'Plano atual' : 'Assinar Premium',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isInitialLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : (status == null || plans == null)
                      ? _PremiumErrorState(
                          message: userVisibleErrorMessage(
                            loadError ??
                                'Falha ao carregar dados de assinatura.',
                            fallback:
                                'Não foi possível carregar os dados de assinatura.',
                          ),
                          onRetry: _refreshBilling,
                        )
                      : _PremiumLoadedView(
                          entryMode: widget.entryMode,
                          status: status,
                          plans: plans,
                          startingCheckout: _startingCheckout,
                          onRefresh: _refreshBilling,
                          onCheckout: _startCheckout,
                          formatDate: _formatDate,
                          findCurrentPlan: _findCurrentPlan,
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumLoadedView extends StatelessWidget {
  const _PremiumLoadedView({
    required this.entryMode,
    required this.status,
    required this.plans,
    required this.startingCheckout,
    required this.onRefresh,
    required this.onCheckout,
    required this.formatDate,
    required this.findCurrentPlan,
  });

  final PremiumEntryMode entryMode;
  final BillingStatus status;
  final List<BillingPlan> plans;
  final bool startingCheckout;
  final Future<void> Function() onRefresh;
  final Future<void> Function(BillingPlan plan) onCheckout;
  final String? Function(String? iso) formatDate;
  final BillingPlan? Function(List<BillingPlan> plans, BillingStatus status)
      findCurrentPlan;

  bool get _isManageMode => entryMode == PremiumEntryMode.manage;

  @override
  Widget build(BuildContext context) {
    final currentPlan = findCurrentPlan(plans, status);
    final orderedPlans = orderBillingPlans(
      plans: plans,
      status: status,
      entryMode: entryMode,
    );
    final displayedPlans = visibleBillingPlans(
      orderedPlans: orderedPlans,
      status: status,
      entryMode: entryMode,
    );
    final hero = buildPremiumHeroContent(
      entryMode: entryMode,
      status: status,
      currentPlan: currentPlan,
      formattedPremiumUntil: formatDate(status.premiumUntil),
    );

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: _isManageMode
            ? [
                _PremiumHero(
                  content: hero,
                  premiumUntil: formatDate(status.premiumUntil),
                ),
                const SizedBox(height: 18),
                _ManageStatusCard(
                  currentPlanName: currentPlan?.name ?? 'Plano grátis',
                  isPremium: status.isPremium,
                  premiumUntil: formatDate(status.premiumUntil),
                ),
                const SizedBox(height: 14),
                _RefreshButton(onRefresh: onRefresh),
                const SizedBox(height: 20),
                Text(
                  status.isPremium ? 'Troca de plano' : 'Assinatura premium',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status.isPremium
                      ? 'Para comparar ou trocar de plano, entre no fluxo comercial dedicado.'
                      : 'A compra agora fica fora desta tela. Use o fluxo Assinar Premium para ver os planos e iniciar checkout.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                _ModeSwitchCard(
                  title: status.isPremium
                      ? 'Ver opcoes de troca'
                      : 'Ir para assinatura',
                  subtitle: status.isPremium
                      ? 'Abra a tela comercial para comparar os planos pagos.'
                      : 'Abra a tela de assinatura para comparar planos e comprar sem redundancia.',
                  buttonLabel: status.isPremium
                      ? 'Abrir fluxo de troca'
                      : 'Abrir fluxo de assinatura',
                  onTap: () => context
                      .push(premiumRouteForEntry(PremiumEntryMode.subscribe)),
                ),
              ]
            : [
                _PremiumHero(
                  content: hero,
                  premiumUntil: formatDate(status.premiumUntil),
                ),
                const SizedBox(height: 18),
                const _SubscribeBenefitsCard(),
                const SizedBox(height: 20),
                Text(
                  status.isPremium ? 'Troque ou renove' : 'Escolha seu plano',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status.isPremium
                      ? 'Seu plano atual continua visivel abaixo, mas esta tela prioriza compra e troca.'
                      : 'Os planos pagos aparecem primeiro para manter o fluxo de compra direto.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                for (final plan in displayedPlans) ...[
                  _BillingPlanCard(
                    plan: plan,
                    status: status,
                    startingCheckout: startingCheckout,
                    onCheckout: onCheckout,
                  ),
                  const SizedBox(height: 14),
                ],
                _CompactCurrentPlan(
                  currentPlanName: currentPlan?.name ??
                      (status.isPremium ? 'Premium' : 'Plano grátis'),
                  premiumUntil: formatDate(status.premiumUntil),
                  isPremium: status.isPremium,
                ),
                const SizedBox(height: 14),
                _RefreshButton(onRefresh: onRefresh),
              ],
      ),
    );
  }
}

class _PremiumHero extends StatelessWidget {
  const _PremiumHero({
    required this.content,
    required this.premiumUntil,
  });

  final PremiumHeroContent content;
  final String? premiumUntil;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: content.gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              content.badgeLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            content.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content.subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (premiumUntil != null) ...[
            const SizedBox(height: 12),
            Text(
              'Valido ate $premiumUntil',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManageStatusCard extends StatelessWidget {
  const _ManageStatusCard({
    required this.currentPlanName,
    required this.isPremium,
    required this.premiumUntil,
  });

  final String currentPlanName;
  final bool isPremium;
  final String? premiumUntil;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPremium ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: isPremium ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  currentPlanName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isPremium
                      ? AppColors.primary.withOpacity(0.14)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isPremium ? 'Premium ativo' : 'Plano grátis',
                  style: TextStyle(
                    color: isPremium ? AppColors.primary : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isPremium
                ? 'Use esta tela para conferir o status da assinatura e avaliar trocas de plano.'
                : 'Use esta tela para acompanhar seu plano atual. Para uma compra nova, use o atalho Assinar Premium no perfil.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (premiumUntil != null) ...[
            const SizedBox(height: 10),
            Text(
              'Renovacao atual ate $premiumUntil',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubscribeBenefitsCard extends StatelessWidget {
  const _SubscribeBenefitsCard();

  @override
  Widget build(BuildContext context) {
    // (label, freeValue, premiumValue)
    const rows = [
      ('Quizzes por dia', '5', 'Ilimitados'),
      ('Simulados por semana', '1', 'Ilimitados'),
      ('Questão dissertativa/semana', '1', 'Ilimitada'),
      ('Modo Infinito', '🔒', '∞'),
      ('Histórico de resultados', '7 dias', 'Completo'),
      ('Ranking global', '🔒', '✓'),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Grátis vs Premium',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          // Header row
          const Row(
            children: [
              Expanded(flex: 4, child: SizedBox.shrink()),
              Expanded(
                flex: 3,
                child: Text(
                  'Grátis',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Premium',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          for (final row in rows) ...[
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    row.$1,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: row.$2 == '🔒'
                          ? AppColors.textSecondary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    row.$3,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ModeSwitchCard extends StatelessWidget {
  const _ModeSwitchCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingPlanCard extends StatelessWidget {
  const _BillingPlanCard({
    required this.plan,
    required this.status,
    required this.startingCheckout,
    required this.onCheckout,
  });

  final BillingPlan plan;
  final BillingStatus status;
  final bool startingCheckout;
  final Future<void> Function(BillingPlan plan) onCheckout;

  @override
  Widget build(BuildContext context) {
    final action = buildPremiumPlanAction(plan: plan, status: status);
    final isCurrentPlan = status.planCode == plan.code;
    final isPaidPlan = plan.priceCents > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrentPlan
              ? AppColors.primary
              : (isPaidPlan
                  ? AppColors.border
                  : AppColors.textDisabled.withOpacity(0.6)),
          width: isCurrentPlan ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.formattedPrice,
                      style: TextStyle(
                        color: isPaidPlan
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCurrentPlan)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Plano atual',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (plan.features.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final feature in plan.features) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !action.enabled || startingCheckout
                    ? null
                    : () => onCheckout(plan),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor:
                      action.enabled ? AppColors.primary : AppColors.surface2,
                  disabledBackgroundColor: AppColors.surface2,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: AppColors.textMuted,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color:
                          action.enabled ? AppColors.primary : AppColors.border,
                    ),
                  ),
                ),
                child: startingCheckout && action.enabled
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        action.label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactCurrentPlan extends StatelessWidget {
  const _CompactCurrentPlan({
    required this.currentPlanName,
    required this.premiumUntil,
    required this.isPremium,
  });

  final String currentPlanName;
  final String? premiumUntil;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status atual do plano',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPremium
                ? '$currentPlanName ativo'
                : 'Plano atual: $currentPlanName',
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (premiumUntil != null) ...[
            const SizedBox(height: 4),
            Text(
              'Validade: $premiumUntil',
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onRefresh,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Text(
          'Atualizar status do plano',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PremiumErrorState extends StatelessWidget {
  const _PremiumErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Falha ao carregar assinatura',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _RefreshButton(onRefresh: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.arrow_back_rounded,
          color: AppColors.textPrimary,
          size: 18,
        ),
      ),
    );
  }
}
