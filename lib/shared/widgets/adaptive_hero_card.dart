import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import 'neo_glass_card.dart';

/// Card de Destaque Inteligente e Adaptativo ao Horário ("Vance Adaptive Hero").
class AdaptiveHeroCard extends StatelessWidget {
  const AdaptiveHeroCard({
    super.key,
    required this.firstName,
    required this.streak,
    this.hasPendingPlan = false,
    this.pendingErrorsCount = 0,
  });

  final String firstName;
  final int streak;
  final bool hasPendingPlan;
  final int pendingErrorsCount;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;

    // Configuração adaptativa baseada no turno e estado
    final (
      String tag,
      String title,
      String subtitle,
      IconData icon,
      Color accentColor,
      VoidCallback action
    ) = _resolveHeroContext(context, hour);

    return NeoGlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      borderRadius: 24,
      hasGlow: true,
      glowColor: accentColor,
      borderGradient: LinearGradient(
        colors: [
          accentColor.withOpacity(0.6),
          accentColor.withOpacity(0.1),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: accentColor.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: Wrap(
                  spacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(icon, color: accentColor, size: 14),
                    const SizedBox(width: 5),
                    Text(
                      tag.toUpperCase(),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (streak > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: AppColors.streakOrange,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '$streak d',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              action();
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor,
                    accentColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Iniciar Sessão de Foco',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, String, String, IconData, Color, VoidCallback) _resolveHeroContext(
    BuildContext context,
    int hour,
  ) {
    if (hour >= 5 && hour < 12) {
      return (
        'Foco Matinal',
        'Hora de ativar o cérebro, $firstName!',
        'Faça 5 a 10 questões para consolidar sua memória e garantir a ofensiva do dia.',
        Icons.wb_sunny_rounded,
        AppColors.primaryLight,
        () => context.push('/quiz'),
      );
    }

    if (hour >= 12 && hour < 18) {
      if (hasPendingPlan) {
        return (
          'Plano do Dia',
          'Sua meta diária está pronta!',
          'Avance no cronograma do seu edital para manter o ritmo acelerado.',
          Icons.event_note_rounded,
          AppColors.accent,
          () => context.push('/today-plan'),
        );
      }
      return (
        'Sprint da Tarde',
        'Consolidação Rápida',
        'Revise as questões erradas ou faça um simulado curto de fixação.',
        Icons.bolt_rounded,
        AppColors.accent,
        () => context.push('/simulado'),
      );
    }

    // Noite
    if (pendingErrorsCount > 0) {
      return (
        'Redenção Noturna',
        'Zere seus pontos cegos',
        'Você tem $pendingErrorsCount ${pendingErrorsCount == 1 ? 'questão' : 'questões'} para resgatar no Caderno de Erros antes de dormir.',
        Icons.nightlight_round,
        AppColors.error,
        () => context.push('/today-plan'),
      );
    }

    return (
      'Revisão Noturna',
      'Fechamento do Dia',
      'Um quiz rápido de revisão garante que o conteúdo seja gravado na memória de longo prazo.',
      Icons.nightlight_round,
      AppColors.primaryLight,
      () => context.push('/quiz'),
    );
  }
}
