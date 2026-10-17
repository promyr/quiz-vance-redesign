import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/widgets/active_plan_card.dart';
import '../../../shared/widgets/adaptive_hero_card.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_shimmer.dart';
import '../../../shared/widgets/bento_tile.dart';
import '../../../shared/widgets/neo_glass_card.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../../shared/widgets/streak_badge.dart';
import '../../error_notebook/providers/error_notebook_provider.dart';
import '../../profile/data/billing_repository.dart';
import '../../profile/presentation/premium_upsell_dialog.dart';
import '../../quiz/providers/quiz_do_dia_provider.dart';

part 'home_action_sections.dart';
part 'home_progress_sections.dart';

class PremiumUpsellDecision {
  const PremiumUpsellDecision._(this.shouldShow);

  const PremiumUpsellDecision.show() : this._(true);

  const PremiumUpsellDecision.skip() : this._(false);

  final bool shouldShow;
}

Future<PremiumUpsellDecision> resolvePremiumUpsellDecision({
  required Future<bool> Function() shouldShowUpsell,
  required Future<BillingStatus> Function() fetchBillingStatus,
}) async {
  final shouldShow = await shouldShowUpsell();
  if (!shouldShow) {
    return const PremiumUpsellDecision.skip();
  }

  try {
    final billingStatus = await fetchBillingStatus();
    if (billingStatus.isPremium) {
      return const PremiumUpsellDecision.skip();
    }
    return const PremiumUpsellDecision.show();
  } catch (_) {
    return const PremiumUpsellDecision.skip();
  }
}

Future<bool> preparePremiumUpsell({
  required Future<bool> Function() shouldShowUpsell,
  required Future<BillingStatus> Function() fetchBillingStatus,
  required Future<void> Function() markUpsellShown,
}) async {
  final decision = await resolvePremiumUpsellDecision(
    shouldShowUpsell: shouldShowUpsell,
    fetchBillingStatus: fetchBillingStatus,
  );
  if (!decision.shouldShow) {
    return false;
  }

  await markUpsellShown();
  return true;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static bool _upsellShownThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowUpsell());
  }

  Future<void> _maybeShowUpsell() async {
    if (_upsellShownThisSession || !mounted) return;

    final shouldShow = await preparePremiumUpsell(
      shouldShowUpsell: shouldShowPremiumUpsell,
      fetchBillingStatus: () => ref.read(billingRepositoryProvider).getStatus(),
      markUpsellShown: markPremiumUpsellShown,
    );
    if (!shouldShow || !mounted) return;

    _upsellShownThisSession = true;
    await showPremiumUpsell(context);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'QV';
    final trimmed = name.trim();
    final parts = trimmed.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _dayOfWeek() {
    const days = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    return days[DateTime.now().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateNotifierProvider).valueOrNull;
    final statsAsync = ref.watch(userStatsNotifierProvider);
    final firstName = authState?.name?.split(' ').first ?? 'Estudante';
    final initials = _initials(authState?.name);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final gridColumns = screenWidth < 360 || textScale > 1.3 ? 1 : 2;
    final gridHeight = 110 + 76 * textScale;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── 1. Top Gamified HUD Header ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => context.go('/profile'),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HOJE · ${_dayOfWeek().toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primaryLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_greeting()}, $firstName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Abrir Ranking e Conquistas',
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          context.push('/ranking');
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.xpGold.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.xpGold.withOpacity(0.4),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: AppColors.xpGold,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Offline banner
            const SliverToBoxAdapter(
              child: OfflineBanner(),
            ),

            // ── 2. Streak & Quota Status Bar ────────────────────────────
            SliverToBoxAdapter(
              child: statsAsync.when(
                data: (stats) {
                  final bool stackCards = screenWidth < 390 || textScale > 1.15;
                  final double card1Width =
                      stackCards ? screenWidth - 40 : (screenWidth - 52) * 0.38;
                  final double card2Width =
                      stackCards ? screenWidth - 40 : (screenWidth - 52) * 0.62;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: card1Width,
                          child: _StreakCard(
                            streak: stats.streak,
                            compact: screenWidth < 420 || textScale > 1.15,
                          ),
                        ),
                        SizedBox(
                          width: card2Width,
                          child: _QuotaBanner(
                            quizRestante: stats.quizRestante ?? 0,
                            quizLimite: stats.quizLimite ?? 0,
                            isPremium: (ref
                                        .watch(authStateNotifierProvider)
                                        .valueOrNull
                                        ?.isAdmin ==
                                    true ||
                                ref
                                        .watch(authStateNotifierProvider)
                                        .valueOrNull
                                        ?.isPremium ==
                                    true ||
                                stats.isPremium ||
                                ref
                                        .watch(billingStatusProvider)
                                        .valueOrNull
                                        ?.isPremium ==
                                    true),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: AppShimmerCard(height: 74),
                ),
                error: (_, __) => const SizedBox(),
              ),
            ),

            // Unified Level, XP & Resolved Questions HUD Bar
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => _XPBar(stats: stats),
                  ) ??
                  const SizedBox(),
            ),

            // Streak Danger Banner (se não estudou hoje e tem streak ativo)
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) {
                      if (stats.streak > 0 && stats.todayQuizzes == 0) {
                        return _StreakDangerBanner(streak: stats.streak);
                      }
                      return const SizedBox.shrink();
                    },
                  ) ??
                  const SizedBox.shrink(),
            ),

            // ── 3. Missão Principal (Plano Ativo + Hero do Turno) ───────
            const SliverToBoxAdapter(
              child: ActivePlanCard(),
            ),

            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => AdaptiveHeroCard(
                      firstName: firstName,
                      streak: stats.streak,
                    ),
                  ) ??
                  const SizedBox(),
            ),

            // Caderno de Erros (Revisão Inteligente de Erros — aparece se houver erros)
            const SliverToBoxAdapter(
              child: _ErrorNotebookBanner(),
            ),

            // Quiz do Dia (Desafio Diário com Bônus de XP)
            const SliverToBoxAdapter(
              child: _QuizDoDiaBanner(),
            ),

            // ── 4. Arena de Prática (Bento Grid 2x2 Equilibrado) ────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 22, 20, 12),
                child: Text(
                  'ARENA DE PRÁTICA',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.count(
                crossAxisCount: gridColumns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: ((screenWidth - 40 - 12 * (gridColumns - 1)) /
                        gridColumns) /
                    gridHeight,
                children: [
                  BentoTile(
                    icon: Icons.bolt_rounded,
                    title: 'Quiz IA Turbo',
                    subtitle: 'Gerado sob medida',
                    badgeText: 'POPULAR',
                    iconColor: AppColors.primaryLight,
                    onTap: () => context.go('/quiz'),
                  ),
                  BentoTile(
                    icon: Icons.edit_note_rounded,
                    title: 'Dissertativo',
                    subtitle: 'Correção por IA',
                    badgeText: 'ABERTO',
                    iconColor: AppColors.accent,
                    onTap: () => context.push('/open-quiz'),
                  ),
                  BentoTile(
                    icon: Icons.timer_rounded,
                    title: 'Simulado Oficial',
                    subtitle: 'Cronômetro real',
                    badgeText: 'RANKEADO',
                    iconColor: AppColors.xpGold,
                    onTap: () => context.go('/simulado'),
                  ),
                  BentoTile(
                    icon: Icons.event_note_rounded,
                    title: 'Plano do Dia',
                    subtitle: 'Trilha do edital',
                    badgeText: 'META',
                    iconColor: AppColors.success,
                    onTap: () => context.push('/today-plan'),
                  ),
                ],
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}
