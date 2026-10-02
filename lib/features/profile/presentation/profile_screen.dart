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
import '../data/billing_repository.dart';
import '../domain/premium_entry_mode.dart';
import '../domain/profile_avatar.dart';

part 'profile_overview_sections.dart';
part 'profile_security_sheets.dart';
part 'profile_settings_sections.dart';

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
                      ? '${authState!.loginId} • Identificador público'
                      : 'Defina seu identificador de login e exibição pública',
                  badgeText:
                      authState?.loginId?.isNotEmpty == true ? 'ativo' : null,
                  badgeColor: AppColors.success,
                  onTap: () => _showChangeLoginIdSheet(context, authState),
                ),
                const _SettingsTile(
                  icon: Icons.devices_rounded,
                  label: 'Sessões ativas',
                  subtitle: 'Gerencie os dispositivos conectados à sua conta',
                  badgeText: 'em breve',
                  badgeColor: AppColors.primaryLight,
                ),
                const _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  label: 'Senha e acesso',
                  subtitle: 'Altere sua senha e proteja sua conta',
                  badgeText: 'em breve',
                  badgeColor: AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'IA e Personalização',
              children: [
                _SettingsTile(
                  icon: Icons.smart_toy_outlined,
                  label: 'Configurações de IA',
                  subtitle:
                      'A IA do Quiz Vance gera e corrige quizzes automaticamente',
                  badgeText: 'Ativa',
                  badgeColor: AppColors.success,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),
            if (authState?.isAdmin == true) ...[
              const SizedBox(height: 14),
              _SettingsSection(
                title: 'ADMINISTRADOR',
                children: [
                  _SettingsTile(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Pool de Chaves Mestras (Fallback)',
                    subtitle:
                        'Gerencie o pool de chaves mestras, prioridade e teste ao vivo',
                    badgeText: 'ADMIN',
                    badgeColor: AppColors.xpGold,
                    onTap: () => context.push('/admin/keys'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Meu Progresso',
              children: [
                _SettingsTile(
                  icon: Icons.insights_rounded,
                  label: 'Estatísticas detalhadas',
                  subtitle: 'Visualizar acurácia e evolução por matéria',
                  onTap: () => context.push('/stats'),
                ),
                _SettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Conquistas',
                  subtitle: 'Emblemas desbravados em quizzes e desafios',
                  onTap: () => context.push('/conquistas'),
                ),
                _SettingsTile(
                  icon: Icons.leaderboard_rounded,
                  label: 'Ranking da comunidade',
                  subtitle: 'Compare seu XP com outros estudantes',
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
                  label: authState?.isAdmin == true
                      ? 'Administrador Geral (Ilimitado)'
                      : (billing?.isPremium == true ||
                              authState?.isPremium == true)
                          ? 'VIP Plus Ativo'
                          : 'Plano grátis',
                  subtitle: authState?.isAdmin == true
                      ? 'Sua conta possui acesso ilimitado e privilégios de administrador'
                      : (billing?.isPremium == true ||
                              authState?.isPremium == true)
                          ? 'Gerencie renovação, benefícios e status da assinatura'
                          : 'Libere limites maiores e recursos premium do Quiz Vance',
                  badgeText: authState?.isAdmin == true
                      ? 'ADM'
                      : (billing?.isPremium == true ||
                              authState?.isPremium == true)
                          ? 'VIP Plus'
                          : _planLabel(billing),
                  badgeColor: authState?.isAdmin == true
                      ? AppColors.xpGold
                      : (billing?.isPremium == true ||
                              authState?.isPremium == true)
                          ? AppColors.primary
                          : _planColor(billing),
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

  static String _planLabel(BillingStatus? status) {
    if (status == null) return 'Carregando';
    return status.isPremium ? 'Premium' : 'Grátis';
  }

  static Color _planColor(BillingStatus? status) {
    if (status?.isPremium == true) return AppColors.primary;
    return AppColors.textMuted;
  }
}
