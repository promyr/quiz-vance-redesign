import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_button.dart';
import '../data/admin_master_keys_service.dart';

class AdminMasterKeysScreen extends ConsumerStatefulWidget {
  const AdminMasterKeysScreen({super.key});

  @override
  ConsumerState<AdminMasterKeysScreen> createState() =>
      _AdminMasterKeysScreenState();
}

class _AdminMasterKeysScreenState extends ConsumerState<AdminMasterKeysScreen> {
  final Map<String, ApiKeyTestResult?> _testResults = {};
  final Map<String, bool> _isTestingMap = {};

  Future<String?> _requestAdminPassword({
    String title = 'Confirmar ação administrativa',
  }) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Senha atual do administrador',
            ),
            onSubmitted: (_) {
              if (controller.text.isNotEmpty) {
                Navigator.of(dialogContext).pop(controller.text);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.isNotEmpty) {
                  Navigator.of(dialogContext).pop(controller.text);
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Não foi possível concluir: $error'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _testKey(MasterApiKeyEntry entry) async {
    final adminPassword =
        await _requestAdminPassword(title: 'Testar chave de IA');
    if (adminPassword == null) return;
    setState(() => _isTestingMap[entry.id] = true);
    try {
      final service = ref.read(adminMasterKeysServiceProvider);
      final result = await service.testApiKey(
        entry.id,
        adminPassword: adminPassword,
      );
      if (mounted) {
        setState(() => _testResults[entry.id] = result);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _isTestingMap[entry.id] = false);
      }
    }
  }

  Future<void> _showAddKeyDialog() async {
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final adminPasswordCtrl = TextEditingController();
    String selectedProvider = 'gemini';
    var isSaving = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppColors.surface,
                title: const Row(
                  children: [
                    Icon(Icons.vpn_key_rounded, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Adicionar Chave Mestra',
                        style: TextStyle(fontSize: 16)),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Provedor de IA',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedProvider,
                        dropdownColor: AppColors.surface,
                        items: const [
                          DropdownMenuItem(
                            value: 'groq',
                            child: Text('Groq (Ultrarrápido)'),
                          ),
                          DropdownMenuItem(
                            value: 'gemini',
                            child: Text('Google Gemini (Recomendado)'),
                          ),
                          DropdownMenuItem(
                            value: 'openai',
                            child: Text('OpenAI'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedProvider = v);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Nome/Rótulo (opcional)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: labelCtrl,
                        decoration: const InputDecoration(
                          hintText: 'ex.: Chave Principal Gemini 1',
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Chave de API (Secret Key)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: keyCtrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        obscureText: true,
                        decoration: const InputDecoration(
                          hintText: 'Cole a chave secreta',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: adminPasswordCtrl,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Senha atual do administrador',
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final key = keyCtrl.text.trim();
                            if (key.isEmpty || adminPasswordCtrl.text.isEmpty) {
                              return;
                            }
                            setDialogState(() => isSaving = true);
                            try {
                              final service =
                                  ref.read(adminMasterKeysServiceProvider);
                              await service.addKey(
                                provider: selectedProvider,
                                apiKey: key,
                                label: labelCtrl.text.trim(),
                                adminPassword: adminPasswordCtrl.text,
                              );
                              ref.invalidate(adminMasterKeysListProvider);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            } catch (error) {
                              _showError(error);
                              if (ctx.mounted) {
                                setDialogState(() => isSaving = false);
                              }
                            }
                          },
                    child: isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Salvar Chave'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      keyCtrl.dispose();
      labelCtrl.dispose();
      adminPasswordCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keysAsync = ref.watch(adminMasterKeysListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pool de Chaves Mestras (Admin)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: keysAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Erro: $err')),
          data: (keys) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info Header Card
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppColors.primary),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Estas chaves mestras são usadas prioritariamente pelo servidor. Se uma chave falhar ou atingir o limite (429), o servidor alterna automaticamente para a próxima chave da lista.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'PRIORIDADE DE EXECUÇÃO (Arraste para reordenar)',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),

                Expanded(
                  child: keys.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.key_off_outlined,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Nenhuma chave mestra cadastrada.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'O app está usando a chave padrão do servidor .env',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 20),
                              AppButton(
                                label: 'Adicionar Primeira Chave',
                                onPressed: _showAddKeyDialog,
                              ),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: keys.length,
                          onReorder: (oldIndex, newIndex) async {
                            final adminPassword = await _requestAdminPassword(
                              title: 'Reordenar chaves de IA',
                            );
                            if (adminPassword == null) return;
                            if (newIndex > oldIndex) newIndex--;
                            final list = List<MasterApiKeyEntry>.from(keys);
                            final item = list.removeAt(oldIndex);
                            list.insert(newIndex, item);

                            final service =
                                ref.read(adminMasterKeysServiceProvider);
                            try {
                              await service.reorderKeys(
                                list,
                                adminPassword: adminPassword,
                              );
                              ref.invalidate(adminMasterKeysListProvider);
                            } catch (error) {
                              _showError(error);
                            }
                          },
                          itemBuilder: (context, index) {
                            final keyEntry = keys[index];
                            final isTesting =
                                _isTestingMap[keyEntry.id] ?? false;
                            final testResult = _testResults[keyEntry.id];

                            final maskedKey = keyEntry.maskedKey;

                            return Container(
                              key: ValueKey(keyEntry.id),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: keyEntry.isActive
                                      ? AppColors.border
                                      : AppColors.border.withOpacity(0.3),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(12),
                                leading: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '#${index + 1}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        keyEntry.label,
                                        style: TextStyle(
                                          color: keyEntry.isActive
                                              ? AppColors.textPrimary
                                              : AppColors.textMuted,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface2,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        keyEntry.provider.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primaryLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      maskedKey,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (testResult != null) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            testResult.isValid
                                                ? Icons.check_circle_rounded
                                                : Icons.error_rounded,
                                            size: 14,
                                            color: testResult.isValid
                                                ? AppColors.success
                                                : AppColors.error,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              testResult.message,
                                              style: TextStyle(
                                                color: testResult.isValid
                                                    ? AppColors.success
                                                    : AppColors.error,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: isTesting
                                              ? null
                                              : () => _testKey(keyEntry),
                                          icon: isTesting
                                              ? const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(
                                                  Icons.bolt_rounded,
                                                  size: 14,
                                                ),
                                          label: Text(
                                            isTesting
                                                ? 'Testando...'
                                                : '⚡ Testar ao Vivo',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                        ),
                                        const Spacer(),
                                        Switch(
                                          value: keyEntry.isActive,
                                          onChanged: (v) async {
                                            final adminPassword =
                                                await _requestAdminPassword(
                                              title: v
                                                  ? 'Ativar chave de IA'
                                                  : 'Desativar chave de IA',
                                            );
                                            if (adminPassword == null) return;
                                            final service = ref.read(
                                                adminMasterKeysServiceProvider);
                                            try {
                                              await service.toggleKeyActive(
                                                keyEntry.id,
                                                v,
                                                adminPassword: adminPassword,
                                              );
                                              ref.invalidate(
                                                  adminMasterKeysListProvider);
                                            } catch (error) {
                                              _showError(error);
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: AppColors.error,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            final adminPassword =
                                                await _requestAdminPassword(
                                              title: 'Excluir chave de IA',
                                            );
                                            if (adminPassword == null) return;
                                            final service = ref.read(
                                                adminMasterKeysServiceProvider);
                                            try {
                                              await service.removeKey(
                                                keyEntry.id,
                                                adminPassword: adminPassword,
                                              );
                                              ref.invalidate(
                                                  adminMasterKeysListProvider);
                                            } catch (error) {
                                              _showError(error);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddKeyDialog,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova Chave Mestra'),
      ),
    );
  }
}
