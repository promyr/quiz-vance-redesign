import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/premium_limit_exception.dart';
import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/library/domain/library_model.dart';
import '../../../features/profile/presentation/premium_upsell_dialog.dart';
import '../../../shared/providers/stats_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/library_source_selector.dart';
import '../application/simulado_generation_coordinator.dart';

/// Tela de configuração do Simulado.
///
/// Permite ao usuário definir:
/// - Fonte do conteúdo: tópico manual ou material da Biblioteca
/// - Dificuldade: Fácil / Médio / Difícil / Misto
/// - Quantidade de questões: 10–60
/// - Duração: 30 min a 3 horas
///
/// Ao confirmar, gera as questões via IA e navega para [SimuladoScreen].
class SimuladoConfigScreen extends ConsumerStatefulWidget {
  const SimuladoConfigScreen({super.key});

  @override
  ConsumerState<SimuladoConfigScreen> createState() =>
      _SimuladoConfigScreenState();
}

class _SimuladoConfigScreenState extends ConsumerState<SimuladoConfigScreen> {
  final _topicCtrl = TextEditingController();

  String _difficulty = 'mixed';
  int _quantity = 30;
  int _durationMinutes = 60;
  bool _loading = false;

  bool _useLibrary = false;
  LibraryFile? _selectedLibraryFile;

  static const _difficulties = ['easy', 'medium', 'hard', 'mixed'];
  static const _difficultyLabels = {
    'easy': 'Fácil',
    'medium': 'Médio',
    'hard': 'Difícil',
    'mixed': 'Misto',
  };

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      final result =
          await ref.read(simuladoGenerationCoordinatorProvider).generateExam(
                useLibrary: _useLibrary,
                topic: _topicCtrl.text,
                difficulty: _difficulty,
                quantity: _quantity,
                durationMinutes: _durationMinutes,
                selectedLibraryFile: _selectedLibraryFile,
              );
      if (mounted) {
        context.goNamed(
          'simuladoSession',
          extra: {
            'questions': result.questions,
            'durationSeconds': result.durationSeconds,
          },
        );
      }
    } on PremiumLimitException catch (_) {
      if (mounted) await showPremiumUpsell(context);
    } catch (e) {
      if (mounted) {
        final message = userVisibleErrorMessage(
          e,
          fallback: 'Não foi possível gerar o simulado. Tente novamente.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/'),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          '←',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    '📝 Novo Simulado',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  const _SimuladoQuotaBadge(),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Conteúdo ──────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card informativo
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Row(
                        children: [
                          Text('⏱️', style: TextStyle(fontSize: 20)),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Simule um exame real com cronômetro e correção automática por IA. Free: 1 simulado por semana. Premium: ilimitado.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Fonte do Conteúdo ─────────────────────────
                    _SectionLabel('Assunto (opcional)'),
                    const SizedBox(height: 10),
                    LibrarySourceSelector(
                      useLibrary: _useLibrary,
                      selectedFile: _selectedLibraryFile,
                      onModeChanged: (v) => setState(() {
                        _useLibrary = v;
                        _selectedLibraryFile = null;
                      }),
                      onFileSelected: (f) =>
                          setState(() => _selectedLibraryFile = f),
                      manualChild: TextFormField(
                        controller: _topicCtrl,
                        decoration: const InputDecoration(
                          hintText:
                              'Opcional — deixe vazio para questões variadas',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Dificuldade ───────────────────────────────
                    _SectionLabel('Dificuldade'),
                    const SizedBox(height: 10),
                    Row(
                      children: _difficulties.map((d) {
                        final isSelected = _difficulty == d;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _difficulty = d),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.15)
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  _difficultyLabels[d] ?? d,
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // ── Quantidade de questões ────────────────────
                    _SectionLabel('Quantidade: $_quantity questões'),
                    Slider(
                      value: _quantity.toDouble(),
                      min: 10,
                      max: 60,
                      divisions: 10,
                      label: '$_quantity',
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _quantity = v.round()),
                    ),
                    const SizedBox(height: 8),

                    // ── Duração ───────────────────────────────────
                    _SectionLabel(
                        'Duração: ${_formatDuration(_durationMinutes)}'),
                    Slider(
                      value: _durationMinutes.toDouble(),
                      min: 30,
                      max: 180,
                      divisions: 6,
                      label: _formatDuration(_durationMinutes),
                      activeColor: AppColors.accent,
                      onChanged: (v) =>
                          setState(() => _durationMinutes = v.round()),
                    ),
                    const SizedBox(height: 32),

                    // ── Resumo ───────────────────────────────────
                    _SummaryCard(
                      quantity: _quantity,
                      difficulty: _difficultyLabels[_difficulty] ?? _difficulty,
                      duration: _formatDuration(_durationMinutes),
                    ),
                    const SizedBox(height: 24),

                    // ── Botão Iniciar ─────────────────────────────
                    AppButton(
                      label: 'Iniciar Simulado',
                      icon: Icons.play_arrow_rounded,
                      isLoading: _loading,
                      onPressed: _start,
                    ),
                  ]
                      .animate(interval: 80.ms)
                      .fadeIn()
                      .slideY(begin: 0.05, end: 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.quantity,
    required this.difficulty,
    required this.duration,
  });

  final int quantity;
  final String difficulty;
  final String duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(icon: '📋', value: '$quantity', label: 'questões'),
          _Divider(),
          _StatItem(icon: '🎯', value: difficulty, label: 'dificuldade'),
          _Divider(),
          _StatItem(icon: '⏱️', value: duration, label: 'duração'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      color: AppColors.primary.withOpacity(0.2),
    );
  }
}

/// Badge compacto que mostra quantos simulados restam hoje para usuários free.
class _SimuladoQuotaBadge extends ConsumerWidget {
  const _SimuladoQuotaBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userStatsNotifierProvider);

    return statsAsync.maybeWhen(
      data: (stats) {
        // Premium ou quota não disponível neste payload: sem badge
        if (stats.isPremium) return const SizedBox.shrink();
        final remaining = stats.simuladoRestanteSemana ?? -1;
        final limit = stats.simuladoLimiteSemana ?? -1;
        if (remaining < 0 || limit < 0) return const SizedBox.shrink();

        final isExhausted = remaining == 0;
        return GestureDetector(
          onTap: () => showPremiumUpsell(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isExhausted
                  ? AppColors.error.withOpacity(0.12)
                  : AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isExhausted
                    ? AppColors.error.withOpacity(0.4)
                    : AppColors.accent.withOpacity(0.3),
              ),
            ),
            child: Text(
              isExhausted ? 'Limite semanal' : '$remaining/$limit esta semana',
              style: TextStyle(
                color: isExhausted ? AppColors.error : AppColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
