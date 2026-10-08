import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/exceptions/remote_service_exception.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../application/premium_checkout_coordinator.dart';
import '../data/billing_repository.dart';
import '../domain/premium_entry_mode.dart';

part 'premium_screen_sections.dart';

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
  bool isAdmin = false,
}) {
  if (isAdmin) {
    return const PremiumHeroContent(
      title: 'Acesso Administrador Geral',
      subtitle:
          'Sua conta possui privilégios de Administrador com acesso total e ilimitado a todas as ferramentas do Quiz Vance.',
      badgeLabel: 'Conta ADM',
      gradient: LinearGradient(
        colors: [AppColors.xpGold, Color(0xFFB8860B)],
      ),
    );
  }

  final currentPlanName = currentPlan?.name ?? 'Premium';

  if (entryMode == PremiumEntryMode.manage) {
    if (status.isPremium) {
      final untilText = formattedPremiumUntil == null
          ? 'Seu acesso Premium está ativo.'
          : 'Seu acesso Premium está ativo até $formattedPremiumUntil.';

      return PremiumHeroContent(
        title: 'Plano atual: $currentPlanName',
        subtitle:
            '$untilText Aproveite todos os recursos ilimitados de estudo.',
        badgeLabel: 'Assinatura Ativa',
        gradient: AppColors.successGradient,
      );
    }

    return const PremiumHeroContent(
      title: 'Você está no plano grátis',
      subtitle:
          'Estude até 10 questões por vez ou assine o Premium por apenas R\$ 14,90/mês para uso ilimitado.',
      badgeLabel: 'Plano Gratuito',
      gradient: AppColors.primaryGradient,
    );
  }

  if (status.isPremium) {
    return const PremiumHeroContent(
      title: 'Seu Premium está ativo',
      subtitle:
          'Confira os benefícios do seu plano atual e acompanhe sua evolução nos estudos.',
      badgeLabel: 'Membro Premium',
      gradient: AppColors.successGradient,
    );
  }

  return const PremiumHeroContent(
    title: 'Quiz Vance Premium',
    subtitle:
        'Quizzes ilimitados com IA, simulados completos e plano de estudo por apenas R\$ 14,90/mês.',
    badgeLabel: 'Oferta Especial',
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
