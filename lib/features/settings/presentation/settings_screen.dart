import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/application/account_scoped_preferences.dart';
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
    final selectedProvider =
        await AccountScopedPreferences.instance.getString('ai_provider') ??
            'gemini';
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
      await AccountScopedPreferences.instance
          .setString('ai_provider', _selectedProvider);
      ref.invalidate(aiProviderSettingProvider);

      // Tenta sincronizar chave pessoal se o usuário tiver configurado uma.
      // Se não tiver, o servidor usa a chave central do Quiz Vance — nenhum bloqueio.
      final guard = ref.read(aiGenerationGuardProvider);
      await guard.markSyncPending();
      final config =
          await guard.loadConfig(overrideProvider: _selectedProvider);

      if (config.hasSelectedProviderKey) {
        // Usuário tem chave pessoal — sincroniza para usar ela no servidor
        await guard.trySyncCurrentConfig(overrideProvider: _selectedProvider);
      }

      return const SyncFeedbackResult(
        state: SyncFeedbackState.fullSuccess,
        message: 'Provedor salvo! A IA do Quiz Vance já está ativa.',
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
              const SizedBox(height: 10),
              // Banner informativo: chave pessoal é OPCIONAL
              GestureDetector(
                onTap: () => context.pushNamed('apiKeys'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.key_outlined,
                          color: AppColors.textMuted,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chave de API pessoal (opcional)',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'O Quiz Vance já usa IA central. Use chave própria para cota extra.',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),

              // Painel Admin: Gerenciador de Chave Central de IA do Servidor
              if (_isAdmin(context)) ...[
                const SizedBox(height: 24),
                _AdminCentralKeyCard(ref: ref),
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

/// Card exclusivo exibido apenas para a conta Admin para alterar a Chave Central do Servidor pelo celular.
class _AdminCentralKeyCard extends ConsumerStatefulWidget {
  const _AdminCentralKeyCard({required this.ref});
  final WidgetRef ref;

  @override
  ConsumerState<_AdminCentralKeyCard> createState() =>
      _AdminCentralKeyCardState();
}

class _AdminCentralKeyCardState extends ConsumerState<_AdminCentralKeyCard> {
  final _keyCtrl = TextEditingController();
  String _provider = 'gemini';
  bool _isSaving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAdminServerKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insira uma chave válida para atualizar o servidor.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final client = ref.read(apiClientProvider);
      // Tenta enviar para o endpoint admin do servidor
      await client.dio.post(
        ApiEndpoints.userAiConfig,
        data: {
          'provider': _provider,
          if (_provider == 'gemini') 'api_key_gemini': key,
          if (_provider == 'openai') 'api_key_openai': key,
          if (_provider == 'groq') 'api_key_groq': key,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Chave central do servidor ($_provider) atualizada com sucesso!'),
          backgroundColor: AppColors.success,
        ),
      );
      _keyCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao atualizar servidor: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PAINEL ADMIN: Chave Central de IA',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Atualize a chave de IA do servidor remotamente pelo app.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Seletor de Provedor
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['groq', 'gemini'].map((p) {
              final selected = _provider == p;
              return FilterChip(
                selected: selected,
                label: Text(p.toUpperCase()),
                selectedColor: AppColors.primary,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                backgroundColor: AppColors.surface,
                onSelected: (val) => setState(() => _provider = p),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Campo para nova chave
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Cole a nova chave API (${_provider.toUpperCase()})...',
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surface,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _isSaving ? null : _saveAdminServerKey,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'Atualizar Chave do Servidor',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
