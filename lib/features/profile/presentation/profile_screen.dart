import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../../shared/providers/user_provider.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_progress_bar.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../auth/domain/auth_state.dart';
import '../../settings/providers/settings_provider.dart';
import '../data/billing_repository.dart';
import '../domain/premium_entry_mode.dart';
import '../domain/profile_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  void _showEditModal(BuildContext context, AuthState? authState) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _EditProfileSheet(
          initialName: authState?.name ?? '',
          initialAvatarUrl: authState?.avatarUrl,
          fallbackName: authState?.name ?? '',
          onSuccess: () => Navigator.of(ctx).pop(),
        );
      },
    );
  }

  void _showChangeLoginIdSheet(BuildContext context, AuthState? authState) {
    if (authState == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ChangeLoginIdSheet(
        currentLoginId: authState.loginId ?? '',
      ),
    );
  }

  void _showDeleteAccountSheet(BuildContext context, AuthState? authState) {
    if (authState == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _DeleteAccountSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateNotifierProvider).valueOrNull;
    final statsAsync = ref.watch(userStatsNotifierProvider);
    final billingAsync = ref.watch(billingStatusProvider);
    final aiProvider =
        ref.watch(aiProviderSettingProvider).valueOrNull ?? 'gemini';
    final stats = statsAsync.valueOrNull;
    final billing = billingAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar perfil',
            onPressed: () => _showEditModal(context, authState),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileHeader(
              authState: authState,
              statsAsync: statsAsync,
              billingAsync: billingAsync,
              onEditTap: () => _showEditModal(context, authState),
            ),
            const SizedBox(height: 16),
            statsAsync.maybeWhen(
              data: (stats) => GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.02,
                children: [
                  _StatTile(
                    label: 'Streak',
                    value: '${stats.streak}d',
                    color: AppColors.streakOrange,
                  ),
                  _StatTile(
                    label: 'Questoes',
                    value: '${stats.totalQuizzes}',
                    color: AppColors.primary,
                  ),
                  _StatTile(
                    label: 'Cards hoje',
                    value: '${stats.flashcardsToday}',
                    color: AppColors.success,
                  ),
                ],
              ),
              orElse: () => GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.02,
                children: const [
                  StatTileSkeleton(),
                  StatTileSkeleton(),
                  StatTileSkeleton(),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (stats?.achievements.isNotEmpty == true)
              _AchievementSummary(achievements: stats!.achievements),
            if (stats?.achievements.isNotEmpty == true)
              const SizedBox(height: 18),
            _SettingsSection(
              title: 'Conta',
              children: [
                _SettingsTile(
                  icon: Icons.badge_outlined,
                  label: 'ID da conta',
                  subtitle: authState?.loginId?.isNotEmpty == true
                      ? '${authState!.loginId} com checagem instantanea de disponibilidade'
                      : 'Defina seu identificador de login e exibicao publica',
                  badgeText:
                      authState?.loginId?.isNotEmpty == true ? 'ativo' : null,
                  badgeColor: AppColors.success,
                  onTap: () => _showChangeLoginIdSheet(context, authState),
                ),
                const _SettingsTile(
                  icon: Icons.devices_rounded,
                  label: 'Sessoes ativas',
                  subtitle:
                      'Gestao de dispositivos e encerramento remoto entram na proxima iteracao',
                  badgeText: 'em breve',
                  badgeColor: AppColors.primaryLight,
                ),
                const _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Senha e acesso',
                  subtitle:
                      'Historico de login e troca de senha entram na mesma evolucao da conta',
                  badgeText: 'em breve',
                  badgeColor: AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'API Keys e IA',
              children: [
                _SettingsTile(
                  icon: Icons.smart_toy_outlined,
                  label: '${_formatProviderName(aiProvider)} principal',
                  subtitle:
                      'Provedor padrao para geracao, correcao e feedback do app',
                  badgeText: _formatProviderName(aiProvider),
                  badgeColor: AppColors.success,
                  onTap: () => context.push('/settings'),
                ),
                _SettingsTile(
                  icon: Icons.key_rounded,
                  label: 'Chaves de API',
                  subtitle:
                      'Configurar OpenAI, Gemini e outros provedores com fallback',
                  badgeText: 'gerenciar',
                  badgeColor: AppColors.xpGold,
                  onTap: () => context.pushNamed('apiKeys'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Meu progresso',
              children: [
                _SettingsTile(
                  icon: Icons.bar_chart_rounded,
                  label: 'Estatisticas detalhadas',
                  subtitle: stats?.taxaAcerto != null
                      ? 'Acuracia ${(stats!.taxaAcerto! * 100).toStringAsFixed(0)}% e evolucao por tema'
                      : 'Acuracia, consistencia, temas fortes e temas fracos',
                  onTap: () => context.push('/stats'),
                ),
                _SettingsTile(
                  icon: Icons.emoji_events_rounded,
                  label: 'Conquistas',
                  subtitle: stats?.achievements.isNotEmpty == true
                      ? '${stats!.achievements.length} marcos liberados ate agora'
                      : 'Marcos destravados e proximos objetivos',
                  onTap: () => context.push('/conquistas'),
                ),
                _SettingsTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Plano de estudo',
                  subtitle: 'Revisar foco da semana e proximos passos',
                  onTap: () => context.push('/study-plan'),
                ),
                _SettingsTile(
                  icon: Icons.leaderboard_rounded,
                  label: 'Ranking com contexto',
                  subtitle: _rankingSubtitle(stats),
                  badgeText: stats == null ? null : '${stats.streak}d',
                  badgeColor: AppColors.success,
                  onTap: () => context.push('/ranking'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Plano',
              children: [
                _SettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  label:
                      billing?.isPremium == true ? 'Premium ativo' : 'Plano gratis',
                  subtitle: billing?.isPremium == true
                      ? 'Gerencie renovacao, beneficios e status da assinatura'
                      : 'Libere limites maiores e recursos premium do Quiz Vance',
                  badgeText: _planLabel(billing),
                  badgeColor: _planColor(billing),
                  onTap: () => context.push(
                    premiumRouteForEntry(PremiumEntryMode.manage),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.rocket_launch_rounded,
                  label: 'Assinar Premium',
                  subtitle:
                      'Upgrade rapido com onboarding de checkout mais claro',
                  badgeText: 'pro',
                  badgeColor: AppColors.primary,
                  onTap: () => context.push(
                    premiumRouteForEntry(PremiumEntryMode.subscribe),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DangerZoneSection(
              onDeleteTap: () => _showDeleteAccountSheet(context, authState),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Sair da conta',
              gradient: const LinearGradient(
                colors: [Color(0xFF333344), Color(0xFF2A2D3E)],
              ),
              onPressed: () async {
                await ref.read(authStateNotifierProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _formatProviderName(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return 'Gemini';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  static String _planLabel(BillingStatus? status) {
    if (status == null) return 'Carregando';
    return status.isPremium ? 'Premium' : 'Gratis';
  }

  static Color _planColor(BillingStatus? status) {
    if (status?.isPremium == true) return AppColors.primary;
    return AppColors.textMuted;
  }

  static String _rankingSubtitle(UserStats? stats) {
    if (stats == null) {
      return 'Veja sua posicao, ritmo recente e o que falta para subir';
    }
    if (stats.streak >= 30) {
      return 'Sequencia forte em ${stats.streak} dias e margem real para subir';
    }
    if (stats.streak >= 7) {
      return 'Voce esta consistente ha ${stats.streak} dias e pode ganhar tracao';
    }
    if (stats.totalQuizzes > 0) {
      return 'Sua base ja existe. Falta transformar volume em constancia';
    }
    return 'Entre no ranking e comece a construir historico competitivo';
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.authState,
    required this.statsAsync,
    required this.billingAsync,
    this.onEditTap,
  });

  final AuthState? authState;
  final AsyncValue<UserStats> statsAsync;
  final AsyncValue<BillingStatus> billingAsync;
  final VoidCallback? onEditTap;

  @override
  Widget build(BuildContext context) {
    final billing = billingAsync.valueOrNull;
    final stats = statsAsync.valueOrNull;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withOpacity(0.22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.16),
            AppColors.surface,
            AppColors.surface2.withOpacity(0.96),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 28,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onEditTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _ProfileAvatar(
                      name: authState?.name,
                      avatarUrl: authState?.avatarUrl,
                      radius: 38,
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.35),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.photo_camera_rounded,
                          color: AppColors.primaryLight,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authState?.name?.trim().isNotEmpty == true
                          ? authState!.name!.trim()
                          : 'Usuario',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _identityLine(authState),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _HeaderBadge(
                          label: billing?.isPremium == true
                              ? 'Premium ativo'
                              : 'Plano gratis',
                          color: billing?.isPremium == true
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                        _HeaderBadge(
                          label: 'Editar perfil',
                          color: AppColors.primaryLight,
                          icon: Icons.edit_outlined,
                          onTap: onEditTap,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (stats == null)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 12, radius: 6),
                SizedBox(height: 10),
                SkeletonBox(height: 8, radius: 4),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.xpGold.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.xpGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _levelLabel(stats),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppProgressBar(
                          value: stats.xpToNextLevel > 0
                              ? (stats.xp / (stats.xp + stats.xpToNextLevel))
                                  .clamp(0.0, 1.0)
                              : 1.0,
                          height: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${stats.xp} XP',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  static String _identityLine(AuthState? authState) {
    final loginId = authState?.loginId?.trim();
    final email = authState?.email?.trim();
    if (loginId != null && loginId.isNotEmpty && email != null && email.isNotEmpty) {
      return 'ID: $loginId  |  $email';
    }
    if (loginId != null && loginId.isNotEmpty) {
      return 'ID: $loginId';
    }
    if (email != null && email.isNotEmpty) {
      return email;
    }
    return 'Complete seu perfil para fortalecer sua identidade na plataforma';
  }

  static String _levelLabel(UserStats stats) {
    final label = stats.levelLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return '$label  •  Nivel ${stats.level}';
    }
    return 'Nivel ${stats.level}';
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({
    required this.label,
    required this.color,
    this.icon,
    this.onTap,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: child,
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    required this.avatarUrl,
    this.radius = 32,
  });

  final String? name;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeProfileAvatarBytes(avatarUrl);
    final normalizedAvatar = avatarUrl?.trim();

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius * 0.6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryLight.withOpacity(0.9),
            AppColors.primary.withOpacity(0.95),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (true) {
        _ when bytes != null => Image.memory(
            bytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _AvatarFallback(name: name),
          ),
        _ when isRemoteProfileAvatar(normalizedAvatar) => Image.network(
            normalizedAvatar!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _AvatarFallback(name: name),
          ),
        _ => _AvatarFallback(name: name),
      },
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name?.trim() ?? '';
    final initials = trimmed.isEmpty
        ? 'Q'
        : trimmed
            .split(RegExp(r'\s+'))
            .where((part) => part.isNotEmpty)
            .take(2)
            .map((part) => part.characters.first.toUpperCase())
            .join();

    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C8CFF), Color(0xFF67C2FF)],
        ),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: initials.length > 1 ? 24 : 28,
        ),
      ),
    );
  }
}

class _AchievementSummary extends StatelessWidget {
  const _AchievementSummary({required this.achievements});

  final List<String> achievements;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONQUISTAS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: achievements
              .map(
                (achievement) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.xpGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.xpGold.withOpacity(0.24),
                    ),
                  ),
                  child: Text(
                    achievement,
                    style: const TextStyle(
                      color: AppColors.xpGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.badgeText,
    this.badgeColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveBadgeColor = badgeColor ?? AppColors.primaryLight;

    return Opacity(
      opacity: enabled ? 1 : 0.82,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.textSecondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (badgeText != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: effectiveBadgeColor.withOpacity(0.13),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: effectiveBadgeColor.withOpacity(0.24),
                              ),
                            ),
                            child: Text(
                              badgeText!,
                              style: TextStyle(
                                color: effectiveBadgeColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                enabled
                    ? Icons.chevron_right_rounded
                    : Icons.lock_clock_outlined,
                color: enabled ? AppColors.textMuted : AppColors.textDisabled,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DangerZoneSection extends StatelessWidget {
  const _DangerZoneSection({required this.onDeleteTap});

  final VoidCallback? onDeleteTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.error.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'ZONA CRITICA',
              style: TextStyle(
                color: AppColors.error.withOpacity(0.92),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          InkWell(
            onTap: onDeleteTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Excluir conta',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Acao permanente com confirmacao forte e sem ambiguidade.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Excluir >',
                    style: TextStyle(
                      color: AppColors.error.withOpacity(0.92),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.initialName,
    required this.initialAvatarUrl,
    required this.fallbackName,
    required this.onSuccess,
  });

  final String initialName;
  final String? initialAvatarUrl;
  final String fallbackName;
  final VoidCallback onSuccess;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const _maxInputBytes = 8 * 1024 * 1024;
  static const _maxDimension = 320;
  static const _jpegQuality = 82;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _avatarCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _processingImage = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _avatarCtrl = TextEditingController(text: widget.initialAvatarUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _avatarCtrl.dispose();
    super.dispose();
  }

  static Uint8List _resizeInBackground(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Formato de imagem nao suportado');
    }

    final resized = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? _maxDimension : -1,
      height: decoded.height >= decoded.width ? _maxDimension : -1,
      interpolation: img.Interpolation.linear,
    );

    return Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality));
  }

  Future<void> _pickAvatar() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (!mounted || result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      final raw = pickedFile.bytes;
      if (raw == null || raw.isEmpty) {
        _showError('Nao foi possivel ler a imagem selecionada.');
        return;
      }

      if (raw.length > _maxInputBytes) {
        _showError('Escolha uma imagem de ate 8 MB.');
        return;
      }

      setState(() => _processingImage = true);
      final compressed = await compute(_resizeInBackground, raw);
      if (!mounted) return;

      _avatarCtrl.text = buildProfileAvatarDataUri(
        bytes: compressed,
        fileName: '${pickedFile.name.split('.').first}.jpg',
      );

      setState(() => _processingImage = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processingImage = false);
      _showError(
        kIsWeb
            ? 'Nao foi possivel abrir a imagem selecionada.'
            : 'Nao foi possivel abrir a galeria do aparelho.',
      );
    }
  }

  void _clearAvatar() {
    _avatarCtrl.clear();
    setState(() {});
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Editar perfil',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _processingImage ? null : _pickAvatar,
                    child: Stack(
                      children: [
                        _ProfileAvatar(
                          name: _nameCtrl.text.trim().isEmpty
                              ? widget.fallbackName
                              : _nameCtrl.text.trim(),
                          avatarUrl: _avatarCtrl.text.trim(),
                          radius: 44,
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(44),
                            ),
                            child: Container(
                              height: 40,
                              color: Colors.black.withOpacity(0.55),
                              alignment: Alignment.center,
                              child: _processingImage
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.photo_camera_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Toque para trocar a foto',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  if (_avatarCtrl.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _clearAvatar,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Remover foto'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Seu nome',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Informe um nome';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            _SaveButton(
              formKey: _formKey,
              nameCtrl: _nameCtrl,
              avatarCtrl: _avatarCtrl,
              onSuccess: widget.onSuccess,
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveButton extends ConsumerStatefulWidget {
  const _SaveButton({
    required this.formKey,
    required this.nameCtrl,
    required this.avatarCtrl,
    required this.onSuccess,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController avatarCtrl;
  final VoidCallback onSuccess;

  @override
  ConsumerState<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends ConsumerState<_SaveButton> {
  bool _saving = false;

  Future<void> _save() async {
    if (!widget.formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(authStateNotifierProvider.notifier).updateProfile(
            name: widget.nameCtrl.text.trim(),
            avatarUrl: widget.avatarCtrl.text.trim().isEmpty
                ? null
                : widget.avatarCtrl.text.trim(),
          );
      if (mounted) widget.onSuccess();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Salvar alteracoes',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
      ),
    );
  }
}

class _ChangeLoginIdSheet extends ConsumerStatefulWidget {
  const _ChangeLoginIdSheet({
    required this.currentLoginId,
  });

  final String currentLoginId;

  @override
  ConsumerState<_ChangeLoginIdSheet> createState() =>
      _ChangeLoginIdSheetState();
}

class _ChangeLoginIdSheetState extends ConsumerState<_ChangeLoginIdSheet> {
  late final TextEditingController _loginIdCtrl;
  final _formKey = GlobalKey<FormState>();
  bool _checking = false;
  bool _saving = false;
  String? _availabilityMessage;
  bool? _isAvailable;

  static final RegExp _loginIdPattern = RegExp(
    r'^[a-zA-Z0-9](?:[a-zA-Z0-9._-]{1,38}[a-zA-Z0-9])?$',
  );

  @override
  void initState() {
    super.initState();
    _loginIdCtrl = TextEditingController(text: widget.currentLoginId);
  }

  @override
  void dispose() {
    _loginIdCtrl.dispose();
    super.dispose();
  }

  String? _validateLoginId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Informe o novo ID';
    if (!_loginIdPattern.hasMatch(text)) {
      return 'Use 3-40 caracteres: letras, numeros, ponto, _ ou -';
    }
    return null;
  }

  Future<void> _checkAvailability() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _checking = true;
      _availabilityMessage = null;
    });

    try {
      final result = await ref
          .read(authStateNotifierProvider.notifier)
          .checkLoginIdAvailability(_loginIdCtrl.text.trim());
      if (!mounted) return;

      setState(() {
        _isAvailable = result.available;
        _availabilityMessage = result.isCurrent
            ? 'Esse ja e o seu ID atual.'
            : result.available
                ? 'ID disponivel para uso.'
                : 'Esse ID ja esta em uso.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isAvailable = false;
        _availabilityMessage = 'Nao foi possivel verificar a disponibilidade.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref
          .read(authStateNotifierProvider.notifier)
          .updateLoginId(loginId: _loginIdCtrl.text.trim());
      if (!mounted) return;

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID da conta atualizado com sucesso.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = !_saving &&
        !_checking &&
        (_isAvailable == true ||
            _loginIdCtrl.text.trim() == widget.currentLoginId);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Alterar ID da conta',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Seu ID e usado para login e exibicao. Verifique a disponibilidade antes de salvar.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _loginIdCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Novo ID',
                hintText: 'ex.: belchior.vance',
                border: OutlineInputBorder(),
              ),
              validator: _validateLoginId,
              onChanged: (_) {
                if (_availabilityMessage != null || _isAvailable != null) {
                  setState(() {
                    _availabilityMessage = null;
                    _isAvailable = null;
                  });
                }
              },
            ),
            if (_availabilityMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _availabilityMessage!,
                style: TextStyle(
                  color:
                      (_isAvailable ?? false) ? AppColors.success : AppColors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _checking || _saving ? null : _checkAvailability,
                    child: _checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Verificar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSave ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Salvar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountSheet extends ConsumerStatefulWidget {
  const _DeleteAccountSheet();

  @override
  ConsumerState<_DeleteAccountSheet> createState() =>
      _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends ConsumerState<_DeleteAccountSheet> {
  final _passwordCtrl = TextEditingController();
  final _confirmationCtrl = TextEditingController();
  bool _deleting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmationCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAccount() async {
    final confirmation = _confirmationCtrl.text.trim().toUpperCase();
    if (_passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe sua senha atual.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (confirmation != 'EXCLUIR') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Digite EXCLUIR para confirmar.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _deleting = true);
    try {
      await ref.read(authStateNotifierProvider.notifier).deleteAccount(
            currentPassword: _passwordCtrl.text,
            confirmationText: _confirmationCtrl.text.trim(),
          );
      if (!mounted) return;

      Navigator.of(context).pop();
      context.go('/login');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conta excluida com sucesso.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Excluir conta',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Essa acao e irreversivel. Informe sua senha atual e digite EXCLUIR para confirmar.',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Senha atual',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirmationCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Digite EXCLUIR',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _deleting ? null : _deleteAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Excluir conta'),
            ),
          ),
        ],
      ),
    );
  }
}
