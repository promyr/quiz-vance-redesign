import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';

/// Card de modo de estudo — suporta emoji, badge "HOT", quota inline e variante featured.
class ModeCard extends StatelessWidget {
  const ModeCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
    this.featured = false,
    this.quotaLabel,
    this.quotaExhausted = false,
  });

  final String emoji;
  final String title;
  final String description;
  final VoidCallback onTap;
  final String? badge;
  final bool featured;

  /// Texto de quota exibido na parte inferior do card.
  /// Ex.: "4/5 hoje" ou "0/1 semana". Null = sem quota visível.
  final String? quotaLabel;

  /// Quando true, o label de quota é mostrado em vermelho (limite atingido).
  final bool quotaExhausted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: featured ? null : AppColors.surface,
          gradient: featured
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.22),
                    AppColors.primary.withOpacity(0.06),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: featured
                ? AppColors.primary.withOpacity(0.5)
                : AppColors.border,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (quotaLabel != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: quotaExhausted
                              ? AppColors.error.withOpacity(0.12)
                              : AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          quotaLabel!,
                          style: TextStyle(
                            color: quotaExhausted
                                ? AppColors.error
                                : AppColors.primaryLight,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            if (badge != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
    );
  }
}
