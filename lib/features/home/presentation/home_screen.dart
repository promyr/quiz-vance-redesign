import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_shimmer.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../error_notebook/providers/error_notebook_provider.dart';
import '../../profile/data/billing_repository.dart';
import '../../profile/presentation/premium_upsell_dialog.dart';
import '../../quiz/providers/quiz_do_dia_provider.dart';

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
                ).animate().fadeIn(duration: 400.ms),
              ),
            ),

            // Offline banner
            const SliverToBoxAdapter(
              child: OfflineBanner(),
            ),

            // Compact stats row
            SliverToBoxAdapter(
              child: statsAsync.when(
                data: (stats) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(
                    children: [
                      // Card 1: Streak
                      Expanded(
                        flex: 1,
                        child: _StreakCard(streak: stats.streak),
                      ),
                      const SizedBox(width: 12),
                      // Card 2: Quota banner
                      Expanded(
                        flex: 2,
                        child: _QuotaBanner(
                          quizRestante: stats.quizRestante ?? 0,
                          quizLimite: stats.quizLimite ?? 0,
                          isPremium: stats.isPremium,
                        ),
                      ),
                    ],
                  ),
                ),
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

            // Priority Action Card
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                    data: (stats) => Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      child: _PriorityActionCard(
                        firstName: firstName,
                        xp: stats.xp,
                        xpToNextLevel: stats.xpToNextLevel,
                        level: stats.level,
                      ),
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

            // Grid com todos os modos de estudo
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
                children: [
                  _HomeModeCard(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Gerar Quiz IA',
                    subtitle: 'Personalizado por IA',
                    badge: 'Popular',
                    color: AppColors.primary,
                    onTap: () => context.go('/quiz'),
                  ),
                  _HomeModeCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Dissertativo',
                    subtitle: 'Questões abertas com IA',
                    badge: 'Novo',
                    color: AppColors.accent,
                    onTap: () => context.push('/open-quiz'),
                  ),
                  _HomeModeCard(
                    icon: Icons.assignment_rounded,
                    title: 'Simulado',
                    subtitle: 'Exame cronometrado',
                    badge: '45 min',
                    color: AppColors.xpGold,
                    onTap: () => context.go('/simulado'),
                  ),
                  _HomeModeCard(
                    icon: Icons.style_rounded,
                    title: 'Flashcards',
                    subtitle: 'Memorização Inteligente',
                    badge: 'Cards',
                    color: AppColors.success,
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
                          const SizedBox(height: 12),
                          _SmartQueueItem(
                            number: 3,
                            title: 'Plano de Estudo',
                            subtitle: 'Acompanhe seu progresso semanal',
                            badgeLabel: 'Plano',
                            badgeColor: AppColors.xpGold,
                            onTap: () => context.push('/study-plan'),
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

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6B6B).withOpacity(0.15),
            const Color(0xFFFF9F43).withOpacity(0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🔥',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            '$streak',
            style: const TextStyle(
              color: AppColors.accent,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text(
            'dias seguidos',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotaBanner extends StatelessWidget {
  const _QuotaBanner({
    required this.quizRestante,
    required this.quizLimite,
    required this.isPremium,
  });

  final int quizRestante;
  final int quizLimite;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.xpGold.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.xpGold.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Premium ativo',
              style: TextStyle(
                color: AppColors.xpGold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '∞',
              style: TextStyle(
                color: AppColors.xpGold,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.xpGold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.xpGold.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$quizRestante de $quizLimite quizzes gratuitos',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Seja Premium →',
                  style: TextStyle(
                    color: AppColors.xpGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _XPBar extends StatelessWidget {
  const _XPBar({required this.stats});
  final dynamic stats;

  @override
  Widget build(BuildContext context) {
    final level = stats.level ?? 1;
    final xp = stats.xp ?? 0;
    final xpToNextLevel = stats.xpToNextLevel ?? 100;
    final progress = xpToNextLevel > 0 ? (xp % 100) / 100.0 : 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '⚡ Nível $level · ${_getRankName(level)}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '+$xp XP',
                  style: const TextStyle(
                    color: AppColors.xpGold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityActionCard extends StatelessWidget {
  const _PriorityActionCard({
    required this.firstName,
    required this.xp,
    required this.xpToNextLevel,
    required this.level,
  });

  final String firstName;
  final int xp;
  final int xpToNextLevel;
  final int level;

  @override
  Widget build(BuildContext context) {
    final progress = xpToNextLevel > 0 ? (xp % 100) / 100.0 : 1.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.35),
          width: 1.5,
        ),
      ),
      child: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF1e1e35), Color(0xFF252245)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Top accent line
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
                gradient: LinearGradient(
                  colors: const [
                    AppColors.primary,
                    AppColors.primaryLight,
                  ],
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '▶ PRÓXIMA AÇÃO',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Continuar estudando',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Estude hoje para manter seu progresso',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 12),
                // Progress bar row
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${(xp % 100).toInt()}/100 XP',
                          style: const TextStyle(
                            color: AppColors.xpGold,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.border,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.primary),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // CTA Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => context.push('/quiz'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '✦ Iniciar agora',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyStat extends StatelessWidget {
  const _WeeklyStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeModeCard extends StatelessWidget {
  const _HomeModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartQueueItem extends StatelessWidget {
  const _SmartQueueItem({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.badgeColor,
    required this.onTap,
  });

  final int number;
  final String title;
  final String subtitle;
  final String badgeLabel;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Number circle
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: badgeColor.withOpacity(0.4)),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card interativo do Caderno de Erros exibido na Home.
class _ErrorNotebookBanner extends ConsumerWidget {
  const _ErrorNotebookBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errorQuestionsAsync = ref.watch(errorNotebookNotifierProvider);
    final questions = errorQuestionsAsync.valueOrNull ?? [];

    if (questions.isEmpty) return const SizedBox.shrink();

    final count = questions.length;
    final topics = questions.map((q) => q.topic).toSet().toList();
    final mainTopic = topics.isNotEmpty ? topics.first : 'Diversos';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Caderno de Erros',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$count ${count == 1 ? 'questão' : 'questões'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Revisar erros de: $mainTopic${topics.length > 1 ? ' e mais' : ''}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              final questionList = questions.map((eq) => eq.question).toList();
              context.push(
                '/quiz/session',
                extra: {
                  'questions': questionList,
                  'infiniteMode': false,
                  'isErrorRevisionMode': true,
                },
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.replay_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Revisar Erros Agora',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.05);
  }
}

/// Card em destaque do Quiz do Dia na Home Screen.
class _QuizDoDiaBanner extends ConsumerWidget {
  const _QuizDoDiaBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyInfoAsync = ref.watch(dailyChallengeNotifierProvider);
    final dailyInfo = dailyInfoAsync.valueOrNull;

    if (dailyInfo == null) return const SizedBox.shrink();

    final isDone = dailyInfo.isCompletedToday;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDone
            ? AppColors.success.withOpacity(0.08)
            : AppColors.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone
              ? AppColors.success.withOpacity(0.35)
              : AppColors.primary.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: isDone
                      ? AppColors.successGradient
                      : AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Quiz do Dia (${dailyInfo.dayName})',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: AppColors.goldGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '+${dailyInfo.bonusXp} XP',
                            style: const TextStyle(
                              color: Color(0xFF1A1200),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dailyInfo.topic,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: isDone
                ? null
                : () {
                    context.push(
                      '/quiz',
                      extra: {
                        'tema': dailyInfo.topic,
                      },
                    );
                  },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: isDone ? null : AppColors.primaryGradient,
                color: isDone ? AppColors.surface2 : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isDone
                          ? Icons.verified_rounded
                          : Icons.play_arrow_rounded,
                      color: isDone ? AppColors.success : Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isDone
                          ? 'Desafio de Hoje Concluído!'
                          : 'Começar Desafio de Hoje',
                      style: TextStyle(
                        color: isDone ? AppColors.textSecondary : Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: -0.05);
  }
}

String _getRankName(int level) {
  if (level >= 25) return 'Mestre';
  if (level >= 20) return 'Diamante';
  if (level >= 15) return 'Platina';
  if (level >= 10) return 'Ouro';
  if (level >= 5) return 'Prata';
  return 'Bronze';
}

class _StreakDangerBanner extends StatelessWidget {
  const _StreakDangerBanner({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5252).withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Text('🔥', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ofensiva de $streak ${streak == 1 ? "dia" : "dias"} em risco!',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Faça 1 quiz rápido hoje para não perder sua sequência.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
