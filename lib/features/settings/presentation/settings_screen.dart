import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/application/account_scoped_preferences.dart';
import '../../../shared/providers/auth_provider.dart';
import '../domain/ai_provider_catalog.dart';
import '../providers/settings_provider.dart';

class _ProviderSaveResult {
  const _ProviderSaveResult({
    required this.succeeded,
    required this.message,
  });

  final bool succeeded;
  final String message;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _selectedProvider = defaultAiProviderId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    final selectedProvider =
        await AccountScopedPreferences.instance.getString('ai_provider') ??
            defaultAiProviderId;
    if (!mounted) return;
    setState(() {
      _selectedProvider = selectedProvider;
      _isLoading = false;
    });
  }

  Future<void> _saveProvider() async {
    final result = await _persistProvider();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.succeeded ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<_ProviderSaveResult> _persistProvider() async {
    try {
      await AccountScopedPreferences.instance
          .setString('ai_provider', _selectedProvider);
      ref.invalidate(aiProviderSettingProvider);

      return const _ProviderSaveResult(
        succeeded: true,
        message: 'Provedor salvo! A IA do Quiz Vance já está ativa.',
      );
    } catch (_) {
      return const _ProviderSaveResult(
        succeeded: false,
        message: 'Não foi possível salvar o provedor selecionado',
      );
    }
  }

  Future<void> _logout() async {
    await ref.read(authStateNotifierProvider.notifier).logout();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding =
        screenWidth > 936 ? (screenWidth - 900) / 2 : 18.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            14,
            horizontalPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () =>
                        context.canPop() ? context.pop() : context.go('/'),
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
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Configurações de IA',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ...aiProviderCatalog.asMap().entries.map((entry) {
                final provider = entry.value;
                final isSelected = provider.id == _selectedProvider;
                return GestureDetector(
                  onTap: () => setState(() => _selectedProvider = provider.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.12)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            isSelected ? AppColors.primary : AppColors.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check_rounded
                                : Icons.smart_toy_outlined,
                            color:
                                isSelected ? Colors.white : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                provider.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                provider.description,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ).animate(delay: (entry.key * 60).ms).fadeIn(),
                );
              }),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _saveProvider,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Salvar preferências',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              // Painel Admin: Gerenciador de Chave Central de IA do Servidor
              if (_isAdmin(context)) ...[
                const SizedBox(height: 24),
                const _AdminMasterKeysEntryCard(),
              ],

              const SizedBox(height: 24),
              GestureDetector(
                onTap: _logout,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: const Center(
                    child: Text(
                      'Sair da conta',
                      style: TextStyle(
                        color: AppColors.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isAdmin(BuildContext context) {
    final authState = ref.read(authStateNotifierProvider).valueOrNull;
    return authState?.isAdmin == true;
  }
}

class _AdminMasterKeysEntryCard extends StatelessWidget {
  const _AdminMasterKeysEntryCard();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => context.pushNamed('adminKeys'),
      tileColor: AppColors.primary.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppColors.primary.withOpacity(0.4),
          width: 1.5,
        ),
      ),
      leading: const Icon(
        Icons.admin_panel_settings_rounded,
        color: AppColors.primary,
      ),
      title: const Text(
        'PAINEL ADMIN: Chaves Centrais de IA',
        style: TextStyle(
          color: AppColors.primaryLight,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: const Text(
        'Gerencie com segurança as chaves usadas pelo servidor.',
        style: TextStyle(color: AppColors.textMuted),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.primary,
      ),
    );
  }
}
