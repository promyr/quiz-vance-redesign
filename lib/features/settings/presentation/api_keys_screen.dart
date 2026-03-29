import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../data/ai_generation_guard.dart';
import '../domain/ai_provider_catalog.dart';
import '../providers/settings_provider.dart';

class ApiKeysScreen extends ConsumerStatefulWidget {
  const ApiKeysScreen({super.key});

  @override
  ConsumerState<ApiKeysScreen> createState() => _ApiKeysScreenState();
}

class _ApiKeysScreenState extends ConsumerState<ApiKeysScreen> {
  static const _storage = FlutterSecureStorage();

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _obscured = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    for (final provider in aiProviderCatalog) {
      _controllers[provider.id] = TextEditingController();
      _obscured[provider.id] = true;
    }
    _loadKeys();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadKeys() async {
    for (final provider in aiProviderCatalog) {
      final value = await _storage.read(key: provider.storageKey) ?? '';
      _controllers[provider.id]!.text = value;
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _saveKeys() async {
    final result = await _persistKeys();

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

  Future<SyncFeedbackResult> _persistKeys() async {
    try {
      for (final provider in aiProviderCatalog) {
        await _storage.write(
          key: provider.storageKey,
          value: _controllers[provider.id]!.text.trim(),
        );
      }

      ref.invalidate(apiKeyGeminiProvider);
      ref.invalidate(apiKeyOpenaiProvider);
      ref.invalidate(apiKeyGroqProvider);

      final guard = ref.read(aiGenerationGuardProvider);
      await guard.markSyncPending();
      final config = await guard.loadConfig();

      if (!config.hasSelectedProviderKey) {
        return SyncFeedbackResult(
          state: SyncFeedbackState.localOnly,
          message:
              'Chaves salvas localmente. Falta configurar uma chave valida para ${config.selectedProviderLabel}.',
        );
      }

      final remoteSynced = await guard.trySyncCurrentConfig();
      if (remoteSynced) {
        return const SyncFeedbackResult(
          state: SyncFeedbackState.fullSuccess,
          message: 'Chaves salvas e sincronizadas com sucesso',
        );
      }

      return const SyncFeedbackResult(
        state: SyncFeedbackState.localOnly,
        message: 'Chaves salvas localmente; sincronizacao pendente',
      );
    } catch (_) {
      return const SyncFeedbackResult(
        state: SyncFeedbackState.failure,
        message: 'Não foi possível salvar as chaves de API',
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o link'),
          backgroundColor: AppColors.accent,
        ),
      );
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
                    'Chaves de API',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Cada provedor abaixo tem link direto para criar a chave e o campo para colar a credencial.',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              ...aiProviderCatalog.asMap().entries.map((entry) {
                final provider = entry.value;
                final controller = _controllers[provider.id]!;
                final obscured = _obscured[provider.id] ?? true;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
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
                        provider.label,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: controller,
                        obscureText: obscured,
                        decoration: InputDecoration(
                          labelText: 'Cole sua chave do ${provider.label}',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() {
                              _obscured[provider.id] = !obscured;
                            }),
                            icon: Icon(
                              obscured
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openUrl(provider.buyUrl),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  gradient: AppColors.primaryGradient,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Criar chave',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openUrl(provider.docsUrl),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Documentacao',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate(delay: (entry.key * 70).ms).fadeIn();
              }),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _saveKeys,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: AppColors.successGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text(
                      'Salvar chaves',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
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
