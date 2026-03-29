import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/mode_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../profile/data/billing_repository.dart';
import '../../profile/presentation/premium_upsell_dialog.dart';

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
  /// Flag de sessão: garante que o popup só apareça uma vez por execução do app.
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
    if (h < 12) return 'Bom dia,';
    if (h < 18) return 'Boa tarde,';
    return 'Boa noite,';
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return 'QV';
    final trimmed = name.trim();
    // Filtra partes vazias (espaços duplos entre palavras)
    final parts = trimmed.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
                      child: Center(
                        child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_greeting(), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        Text('$firstName 👋', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    statsAsync.whenOrNull(
                      data: (s) => Row(children: [
                        _Chip(icon: '🔥', value: '${s.streak}'),
                        const SizedBox(width: 6),
                        _Chip(icon: '⚡', value: s.xp >= 1000 ? '${(s.xp / 1000).toStringAsFixed(1)}k' : '${s.xp}'),
                      ]),
                    ) ?? const SizedBox(),
                  ],
                ).animate().fadeIn(duration: 400.ms),
              ),
            ),

            // Streak Banner
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                data: (s) => s.streak > 0 ? Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [const Color(0xFFFF6B6B).withOpacity(0.13), const Color(0xFFFF9F43).withOpacity(0.08)]),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Text('🔥', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${s.streak} dias seguidos!', style: const TextStyle(color: AppColors.accent, fontSize: 17, fontWeight: FontWeight.w900)),
                          const Text('Estude hoje para manter seu streak', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                        ]),
                      ),
                    ]),
                  ),
                ) : const SizedBox(),
              ) ?? const SizedBox(),
            ),

            // XP Card
            SliverToBoxAdapter(
              child: statsAsync.whenOrNull(
                data: (s) => Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('⚡ Nível ${s.level}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('+${s.xp} XP', style: const TextStyle(color: AppColors.xpGold, fontSize: 12, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: s.xpToNextLevel > 0 ? (s.xp % 100) / 100.0 : 1.0,
                          backgroundColor: AppColors.border,
                          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                          minHeight: 8,
                        ),
                      ),
                    ]),
                  ),
                ),
              ) ?? const SizedBox(),
            ),

            // Trial / free-tier awareness banner
            SliverToBoxAdapter(
              child: _TrialBanner(onUpgradeTap: () => context.push('/premium')),
            ),

            // Section label
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                child: const Text('MODOS DE ESTUDO',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ),
            ),

            // Mode grid — quotas inline para Quiz, Simulado e Dissertativo
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: statsAsync.maybeWhen(
                data: (stats) {
                  // Calcula labels de quota apenas para usuários free
                  String? quizLabel;
                  bool quizExhausted = false;
                  String? simuladoLabel;
                  bool simuladoExhausted = false;
                  String? openQuizLabel;
                  bool openQuizExhausted = false;

                  if (!stats.isPremium) {
                    final qr = stats.quizRestante ?? -1;
                    final ql = stats.quizLimite ?? -1;
                    if (qr >= 0 && ql > 0) {
                      quizLabel = '$qr/$ql hoje';
                      quizExhausted = qr == 0;
                    }

                    final sr = stats.simuladoRestanteSemana ?? -1;
                    final sl = stats.simuladoLimiteSemana ?? -1;
                    if (sr >= 0 && sl > 0) {
                      simuladoLabel = '$sr/$sl semana';
                      simuladoExhausted = sr == 0;
                    }

                    final or_ = stats.openQuizRestanteSemana ?? -1;
                    final ol = stats.openQuizLimiteSemana ?? -1;
                    if (or_ >= 0 && ol > 0) {
                      openQuizLabel = '$or_/$ol semana';
                      openQuizExhausted = or_ == 0;
                    }
                  }

                  return SliverGrid.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.05,
                    children: [
                      ModeCard(emoji: '🧠', title: 'Quiz IA', description: 'Questões geradas por IA', featured: true, badge: 'HOT', quotaLabel: quizLabel, quotaExhausted: quizExhausted, onTap: () => context.go('/quiz')),
                      ModeCard(emoji: '🗂️', title: 'Flashcards', description: 'Repetição espaçada SRS', onTap: () => context.go('/flashcards')),
                      ModeCard(emoji: '📚', title: 'Biblioteca', description: 'Materiais e pacotes de estudo', onTap: () => context.go('/library')),
                      ModeCard(emoji: '📝', title: 'Simulado', description: 'Exame completo cronometrado', quotaLabel: simuladoLabel, quotaExhausted: simuladoExhausted, onTap: () => context.go('/simulado')),
                      ModeCard(emoji: '📅', title: 'Plano de Estudo', description: 'Plano personalizado com IA', onTap: () => context.push('/study-plan')),
                      ModeCard(emoji: '✍️', title: 'Dissertativo', description: 'Questões abertas com IA', quotaLabel: openQuizLabel, quotaExhausted: openQuizExhausted, onTap: () => context.push('/open-quiz')),
                    ],
                  );
                },
                orElse: () => SliverGrid.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.15,
                  children: const [
                    ModeCardSkeleton(),
                    ModeCardSkeleton(),
                    ModeCardSkeleton(),
                    ModeCardSkeleton(),
                    ModeCardSkeleton(),
                    ModeCardSkeleton(),
                  ],
                ),
              ),
            ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
      ),
    );
  }
}

/// Banner contextual que mostra quota restante de quizzes para usuários free.
/// Exibe mensagem de trial para novos usuários (< 3 dias de conta).
/// Torna-se invisível quando o usuário é Premium.
class _TrialBanner extends ConsumerWidget {
  const _TrialBanner({required this.onUpgradeTap});
  final VoidCallback onUpgradeTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsNotifierProvider);

    return statsAsync.maybeWhen(
      data: (stats) {
        // Premium ou quota não disponível neste payload: sem banner
        if (stats.isPremium) return const SizedBox.shrink();

        final remaining = stats.quizRestante ?? -1;
        final limit = stats.quizLimite ?? -1;
        if (remaining < 0 || limit < 0) return const SizedBox.shrink();

        final isExhausted = remaining == 0;
        final bgColor = isExhausted
            ? const Color(0xFFFF6B6B).withOpacity(0.10)
            : const Color(0xFFFFE66D).withOpacity(0.08);
        final borderColor = isExhausted
            ? AppColors.error.withOpacity(0.3)
            : const Color(0xFFFFE66D).withOpacity(0.35);
        final icon = isExhausted ? '🚫' : '⚡';
        final message = isExhausted
            ? 'Você atingiu o limite de $limit quizzes hoje.'
            : 'Você tem $remaining de $limit quizzes gratuitos hoje.';
        final cta = isExhausted ? 'Seja Premium →' : 'Seja Premium ilimitado →';

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
          child: GestureDetector(
            onTap: onUpgradeTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cta,
                          style: const TextStyle(
                            color: Color(0xFFFFE66D),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.value});
  final String icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
