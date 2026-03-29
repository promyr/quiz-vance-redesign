import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Chip de streak (fogo) e XP — reutilizável no header de todas as telas.
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.value,
    required this.icon,
    required this.color,
    this.label,
  });

  const StatChip.streak({super.key, required int days})
      : value = '$days',
        icon = Icons.local_fire_department_rounded,
        color = AppColors.streakOrange,
        label = null;

  const StatChip.xp({super.key, required int xp})
      : value = '$xp XP',
        icon = Icons.bolt_rounded,
        color = AppColors.xpGold,
        label = null;

  final String value;
  final IconData icon;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (label != null) ...[
            const SizedBox(width: 3),
            Text(
              label!,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
