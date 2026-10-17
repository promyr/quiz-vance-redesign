import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'neo_glass_card.dart';

/// Bloco do Bento Grid com suporte a layout vertical, badge, gradientes e contadores.
class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badgeText,
    this.badgeColor,
    this.iconColor,
    this.iconBackgroundColor,
    this.gradient,
    this.trailing,
    this.onTap,
    this.flex = 1,
    this.height,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? badgeText;
  final Color? badgeColor;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final Gradient? gradient;
  final Widget? trailing;
  final VoidCallback? onTap;
  final int flex;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? AppColors.primary;
    final effectiveIconBg =
        iconBackgroundColor ?? effectiveIconColor.withOpacity(0.12);

    return Semantics(
      button: true,
      label:
          '$title. $subtitle. ${badgeText != null ? "Status: $badgeText" : ""}',
      child: NeoGlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        borderRadius: 20,
        hasGlow: true,
        glowColor: effectiveIconColor,
        borderGradient: LinearGradient(
          colors: [
            effectiveIconColor.withOpacity(0.45),
            AppColors.border,
          ],
        ),
        child: SizedBox(
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: effectiveIconBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: effectiveIconColor.withOpacity(0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: effectiveIconColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (badgeText != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? effectiveIconColor)
                                  .withOpacity(0.16),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (badgeColor ?? effectiveIconColor)
                                    .withOpacity(0.38),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              badgeText!,
                              style: TextStyle(
                                color: badgeColor ?? effectiveIconColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (trailing != null)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing!,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
