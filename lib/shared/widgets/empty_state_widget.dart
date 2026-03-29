/// Widget reutilizável para estados vazios em listas, históricos, etc.
///
/// Uso básico:
/// ```dart
/// EmptyStateWidget(
///   emoji: '📭',
///   title: 'Nenhum resultado',
///   subtitle: 'Faça seu primeiro quiz para ver o histórico aqui.',
/// )
/// ```
///
/// Com CTA:
/// ```dart
/// EmptyStateWidget(
///   emoji: '🧠',
///   title: 'Nenhum quiz realizado',
///   subtitle: 'Crie um quiz agora e comece a estudar.',
///   ctaLabel: 'Criar Quiz',
///   onCtaTap: () => context.go('/quiz'),
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({
    super.key,
    required this.emoji,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
    this.compact = false,
  });

  /// Emoji grande exibido como ícone visual do estado vazio.
  final String emoji;

  /// Título principal do estado vazio.
  final String title;

  /// Texto de apoio opcional, exibido abaixo do título.
  final String? subtitle;

  /// Rótulo do botão de ação (CTA). Exibido apenas se [onCtaTap] for informado.
  final String? ctaLabel;

  /// Callback do botão de ação. Se null, nenhum botão é exibido.
  final VoidCallback? onCtaTap;

  /// Quando true, reduz padding e tamanhos para uso em listas compactas.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final emojiSize = compact ? 38.0 : 52.0;
    final titleSize = compact ? 14.0 : 16.0;
    final subtitleSize = compact ? 12.0 : 13.0;
    final vertPad = compact ? 24.0 : 48.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: vertPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ícone emoji
          Text(emoji, style: TextStyle(fontSize: emojiSize))
              .animate()
              .scale(duration: 400.ms, curve: Curves.elasticOut),

          SizedBox(height: compact ? 12 : 20),

          // Título
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: titleSize,
              fontWeight: FontWeight.w700,
            ),
          )
              .animate()
              .fadeIn(delay: 80.ms)
              .slideY(begin: 0.05, end: 0),

          // Subtítulo
          if (subtitle != null) ...[
            SizedBox(height: compact ? 6 : 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: subtitleSize,
                height: 1.5,
              ),
            )
                .animate()
                .fadeIn(delay: 140.ms),
          ],

          // CTA
          if (onCtaTap != null && ctaLabel != null) ...[
            SizedBox(height: compact ? 16 : 24),
            GestureDetector(
              onTap: onCtaTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  ctaLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
                .animate()
                .fadeIn(delay: 200.ms)
                .slideY(begin: 0.06, end: 0),
          ],
        ],
      ),
    );
  }
}
