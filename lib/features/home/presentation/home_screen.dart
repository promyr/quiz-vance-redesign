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
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
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
                            'Hoje, ${_dayOfWeek()}',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${_greeting()}, $firstName',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_none,
                          color: AppColors.textMuted),
                      onPressed: () {},
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),

            // Offline banner
            const SliverToBoxAdapter(
              child: OfflineBanner(),
            ),

            // Compact stats row
            SliverToBoxAdapter(
              child: statsAsync.when(
                data: (stats) {
                  final bool stackCards = screenWidth < 390 || textScale > 1.15;
                  final double card1Width = stackCards
                      ? screenWidth - 40
                      : (screenWidth - 52) * 0.38;
                  final double card2Width = stackCards
                      ? screenWidth - 40
                      : (screenWidth - 52) * 0.62;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        // Card 1: Streak
                        SizedBox(
                          width: card1Width,
                          child: _StreakCard(
                            streak: stats.streak,
                            compact: screenWidth < 420 || textScale > 1.15,
                          ),
                        ),
                        // Card 2: Quota banner
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

            // XP Bar
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => _XPBar(stats: stats),
                  ) ??
                  const SizedBox(),
            ),

            // Card de Destaque: Continuar Plano de Estudos
            const SliverToBoxAdapter(
              child: ActivePlanCard(),
            ),

            // Streak Danger Banner (se não estudou hoje e tem streak ativo)
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) {
                      if (stats.streak > 0 &&
                          stats.quizRestante != null &&
                          stats.quizLimite != null &&
                          stats.quizRestante == stats.quizLimite) {
                        return _StreakDangerBanner(streak: stats.streak);
                      }
                      return const SizedBox.shrink();
                    },
                  ) ??
                  const SizedBox.shrink(),
            ),

            // Adaptive Hero Card (Missão do Turno)
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => AdaptiveHeroCard(
                      firstName: firstName,
                      streak: stats.streak,
                    ),
                  ) ??
                  const SizedBox(),
            ),

            // Section label: ESTA SEMANA
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: const Text(
                  'ESTA SEMANA',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            // Meta semanal row
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: _WeeklyStat(
                              value: stats.totalQuizzes.toString(),
                              label: 'Questões',
                              color: AppColors.primaryLight,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _WeeklyStat(
                              value: stats.streak.toString(),
                              label: 'Dias',
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _WeeklyStat(
                              value: stats.xp.toString(),
                              label: 'XP',
                              color: AppColors.xpGold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ) ??
                  const SizedBox(),
            ),

            // Quiz do Dia (Desafio Coletivo Diário)
            const SliverToBoxAdapter(
              child: _QuizDoDiaBanner(),
            ),

            // Caderno de Erros (Revisão Inteligente de Erros)
            const SliverToBoxAdapter(
              child: _ErrorNotebookBanner(),
            ),

            // Section label: MODOS DE ESTUDO & GERAÇÃO DE PERGUNTAS
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Text(
                  'MODOS DE ESTUDO & GERAÇÃO DE PERGUNTAS',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            // Bento Grid com os modos rápidos de estudo
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
                    icon: Icons.auto_awesome_rounded,
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
                    badgeText: 'NOVO',
                    iconColor: AppColors.accent,
                    onTap: () => context.push('/open-quiz'),
                  ),
                  BentoTile(
                    icon: Icons.assignment_rounded,
                    title: 'Simulado Oficial',
                    subtitle: 'Cronômetro real',
                    badgeText: 'RANKEADO',
                    iconColor: AppColors.xpGold,
                    onTap: () => context.go('/simulado'),
                  ),
                  BentoTile(
                    icon: Icons.style_rounded,
                    title: 'Flashcards SRS',
                    subtitle: 'Repetição espaçada',
                    badgeText: 'MEMÓRIA',
                    iconColor: AppColors.success,
                    onTap: () => context.go('/flashcards'),
                  ),
                ],
              ),
            ),

            // Section label: SUA TRILHA DE HOJE
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 28, 20, 16),
                child: Text(
                  'SUA TRILHA DE HOJE',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            // Smart Queue items
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          _SmartQueueItem(
                            number: 1,
                            title: 'Quiz IA disponível',
                            subtitle:
                                'Personalizado para você · ${stats.quizRestante ?? 0} restantes hoje',
                            badgeLabel: 'Quiz',
                            badgeColor: AppColors.primary,
                            onTap: () => context.go('/quiz'),
                          ),
                          const SizedBox(height: 12),
                          _SmartQueueItem(
                            number: 2,
                            title: 'Flashcards de Revisão',
                            subtitle: 'Revise cards pendentes do seu deck',
                            badgeLabel: 'Cards',
                            badgeColor: AppColors.success,
                            onTap: () => context.go('/flashcards'),
                          ),
                        ],
                      ),
                    ),
                  ) ??
                  const SizedBox(),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}
