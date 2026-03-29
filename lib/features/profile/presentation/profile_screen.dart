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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateNotifierProvider).valueOrNull;
    final statsAsync = ref.watch(userStatsNotifierProvider);
    final billingAsync = ref.watch(billingStatusProvider);
    final aiProvider =
        ref.watch(aiProviderSettingProvider).valueOrNull ?? 'gemini';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar perfil',
            onPressed: () => _showEditModal(context, authState),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _ProfileHeader(
              authState: authState,
              statsAsync: statsAsync,
              billingAsync: billingAsync,
              onEditTap: () => _showEditModal(context, authState),
            ),
            const SizedBox(height: 20),
            statsAsync.maybeWhen(
              data: (stats) => GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.18,
                children: [
                  _StatTile(
                    label: 'Streak',
                    value: '${stats.streak}d',
                    color: AppColors.streakOrange,
                  ),
                  _StatTile(
                    label: 'Questões',
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
                childAspectRatio: 1.18,
                children: const [
                  StatTileSkeleton(),
                  StatTileSkeleton(),
                  StatTileSkeleton(),
                ],
              ),
            ),
            const SizedBox(height: 20),
            statsAsync.whenOrNull(
                  data: (stats) => stats.achievements.isNotEmpty
                      ? _AchievementSummary(achievements: stats.achievements)
                      : const SizedBox.shrink(),
                ) ??
                const SizedBox.shrink(),
            const SizedBox(height: 20),
            _SettingsSection(
              title: 'Meu progresso',
              children: [
                _SettingsTile(
                  icon: Icons.bar_chart_rounded,
                  label: 'Estatísticas detalhadas',
                  trailing: '',
                  onTap: () => context.push('/stats'),
                ),
                _SettingsTile(
                  icon: Icons.emoji_events_rounded,
                  label: 'Conquistas',
                  trailing: '',
                  onTap: () => context.push('/conquistas'),
                ),
                _SettingsTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Plano de estudo',
                  trailing: '',
                  onTap: () => context.push('/study-plan'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsSection(
              title: 'Configurações de IA',
              children: [
                _SettingsTile(
                  icon: Icons.smart_toy_outlined,
                  label: 'Provedor padrao',
                  trailing: _formatProviderName(aiProvider),
                  onTap: () => context.push('/settings'),
                ),
                _SettingsTile(
                  icon: Icons.key_rounded,
                  label: 'Chaves de API',
                  trailing: '',
                  onTap: () => context.push('/settings/api-keys'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsSection(
              title: 'Plano',
              children: [
                _SettingsTile(
                  icon: Icons.workspace_premium_rounded,
                  label: 'Plano atual',
                  trailing: _planLabel(billingAsync.valueOrNull),
                  trailingColor: _planColor(billingAsync.valueOrNull),
                  onTap: () => context.push(
                    premiumRouteForEntry(PremiumEntryMode.manage),
                  ),
                ),
                _SettingsTile(
                  icon: Icons.rocket_launch_rounded,
                  label: 'Assinar Premium',
                  trailing: '',
                  trailingColor: AppColors.primary,
                  onTap: () => context.push(
                    premiumRouteForEntry(PremiumEntryMode.subscribe),
                  ),
                ),
              ],
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
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  static String _formatProviderName(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return 'Gemini';
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  static String _planLabel(BillingStatus? status) {
    if (status == null) {
      return 'Carregando...';
    }
    if (status.isPremium) {
      return 'Premium';
    }
    return 'Grátis';
  }

  static Color _planColor(BillingStatus? status) {
    if (status?.isPremium == true) {
      return AppColors.primary;
    }
    return AppColors.textMuted;
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Avatar clicável — abre o editor diretamente
          GestureDetector(
            onTap: onEditTap,
            child: Stack(
              children: [
                _ProfileAvatar(
                  name: authState?.name,
                  avatarUrl: authState?.avatarUrl,
                  radius: 44,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 2),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            authState?.name ?? 'Usuario',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          GestureDetector(
            onTap: onEditTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, size: 13, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'Editar perfil',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (authState?.loginId?.isNotEmpty == true)
            Text(
              'ID: ${authState!.loginId}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          Text(
            authState?.email ?? '',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (billing?.isPremium ?? false)
                  ? AppColors.primary.withOpacity(0.12)
                  : AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: (billing?.isPremium ?? false)
                    ? AppColors.primary.withOpacity(0.35)
                    : AppColors.border,
              ),
            ),
            child: Text(
              billing?.isPremium == true ? 'Premium ativo' : 'Plano grátis',
              style: TextStyle(
                color: billing?.isPremium == true
                    ? AppColors.primary
                    : AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          statsAsync.maybeWhen(
            data: (stats) => Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      stats.levelLabel?.isNotEmpty == true
                          ? '${stats.levelLabel} (${stats.level})'
                          : 'Nivel ${stats.level}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${stats.xp} XP',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AppProgressBar(
                  value: stats.xpToNextLevel > 0
                      ? stats.xp / (stats.xp + stats.xpToNextLevel)
                      : 1.0,
                  height: 8,
                ),
              ],
            ),
            orElse: () => const Column(
              children: [
                SkeletonBox(width: 100, height: 12, radius: 6),
                SizedBox(height: 8),
                SkeletonBox(height: 8, radius: 4),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    required this.avatarUrl,
    required this.radius,
  });

  final String? name;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatarBytes = decodeProfileAvatarBytes(avatarUrl);
    final size = radius * 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withOpacity(0.2),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildAvatarContent(avatarBytes),
    );
  }

  Widget _buildAvatarContent(Uint8List? avatarBytes) {
    if (avatarBytes != null) {
      return Image.memory(
        avatarBytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    if (isRemoteProfileAvatar(avatarUrl)) {
      return Image.network(
        avatarUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _AvatarFallback(name: name),
      );
    }

    return _AvatarFallback(name: name);
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final initial = name != null && name!.trim().isNotEmpty
        ? name!.trim()[0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 36,
          fontWeight: FontWeight.w800,
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
        Text('Conquistas', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: achievements
              .map(
                (achievement) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.xpGold.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.xpGold.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    achievement,
                    style: const TextStyle(
                      color: AppColors.xpGold,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textMuted),
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textMuted),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: children),
        ),
      ],
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
  // Limite de entrada — recusa arquivos muito grandes antes de processar
  static const _maxInputBytes = 8 * 1024 * 1024; // 8 MB
  // Tamanho máximo em pixels do lado maior após resize
  static const _maxDimension = 320;
  // Qualidade JPEG do output (0–100)
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

  /// Redimensiona e comprime a imagem em um isolate para não travar a UI.
  static Uint8List _resizeInBackground(Uint8List input) {
    final decoded = img.decodeImage(input);
    if (decoded == null) throw Exception('Formato de imagem não suportado');
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
        _showMessage('Não foi possível ler a imagem selecionada.');
        return;
      }

      if (raw.length > _maxInputBytes) {
        _showMessage('Escolha uma imagem de até 8 MB.');
        return;
      }

      setState(() => _processingImage = true);

      // Resize/compressão em isolate para não bloquear a UI
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
      _showMessage('Não foi possível abrir a galeria do aparelho.');
    }
  }

  void _clearAvatar() {
    _avatarCtrl.clear();
    setState(() {});
  }

  void _showMessage(String message) {
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
            // ── Avatar clicável direto — toca para trocar ─────────────────
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
                        // Semicírculo escuro inferior com ícone de câmera
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
            // ── Nome ──────────────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Seu nome',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Informe um nome';
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $e'),
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
                'Salvar â€‹lteraÃ§Ãµes',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.trailing,
    this.trailingColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String trailing;
  final Color? trailingColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(
        label,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing.isEmpty
          ? const Icon(Icons.chevron_right_rounded,
              color: AppColors.textMuted, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  trailing,
                  style: TextStyle(
                    color: trailingColor ?? AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 18),
              ],
            ),
      onTap: onTap,
    );
  }
}
