import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/providers/auth_provider.dart';
import '../data/ai_generation_guard.dart';
import '../domain/ai_provider_catalog.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _selectedProvider = 'gemini';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedProvider = prefs.getString('ai_provider') ?? 'gemini';
      _isLoading = false;
    });
  }

  Future<void> _saveProvider() async {
    final result = await _persistProvider();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isFullSuccess
            ? AppColors.success
            : result.isLocalOnly
                ? AppColors.accent
                : AppColors.error,
      ),
    );
  }

  Future<SyncFeedbackResult> _persistProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_provider', _selectedProvider);
      ref.invalidate(aiProviderSettingProvider);

      final guard = ref.read(aiGenerationGuardProvider);
      await guard.markSyncPending();
      final config = await guard.loadConfig(overrideProvider: _selectedProvider);

      if (!config.hasSelectedProviderKey) {
        return SyncFeedbackResult(
          state: SyncFeedbackState.localOnly,
          message:
              'Provedor salvo localmente. Falta configurar a chave do ${config.selectedProviderLabel}.',
        );
      }

      final remoteSynced =
          await guard.trySyncCurrentConfig(overrideProvider: _selectedProvider);
      if (remoteSynced) {
        return const SyncFeedbackResult(
          state: SyncFeedbackState.fullSuccess,
          message: 'Provedor salvo e sincronizado com sucesso',
        );
      }

      return const SyncFeedbackResult(
        state: SyncFeedbackState.localOnly,
        message: 'Provedor salvo localmente; sincronizacao pendente',
      );
    } catch (_) {
      return const SyncFeedbackResult(
        state: SyncFeedbackState.failure,
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

    final selected = aiProviderCatalog.firstWhere(
      (provider) => provider.id == _selectedProvider,
      orElse: () => aiProviderCatalog.first,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
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
                    'Provedor padrao',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selected.description,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const SizedBox(height: 18),
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
                      'Salvar provedor',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => context.push('/settings/api-keys'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Text(
                      'Ir para chaves de API',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
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
}
