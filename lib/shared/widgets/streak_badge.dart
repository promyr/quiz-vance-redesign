import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Badge de Streak Gamificado com animação de pulso/chama ("Streak on Fire").
class StreakBadge extends StatefulWidget {
  const StreakBadge({
    super.key,
    required this.streak,
    this.isActiveToday = true,
    this.compact = false,
  });

  final int streak;
  final bool isActiveToday;
  final bool compact;

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(begin: 0.2, end: 0.6).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasStreak = widget.streak > 0;
    final flameColor = hasStreak ? AppColors.streakOrange : AppColors.textDisabled;

    if (widget.compact) {
      return AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: flameColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: flameColor.withOpacity(hasStreak ? _glowAnim.value : 0.2),
              width: 1.2,
            ),
            boxShadow: hasStreak
                ? [
                    BoxShadow(
                      color: flameColor.withOpacity(_glowAnim.value * 0.4),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: flameColor,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${widget.streak}',
                style: TextStyle(
                  color: hasStreak ? AppColors.textPrimary : AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              flameColor.withOpacity(0.2),
              flameColor.withOpacity(0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: flameColor.withOpacity(hasStreak ? _glowAnim.value : 0.3),
            width: 1.5,
          ),
          boxShadow: hasStreak
              ? [
                  BoxShadow(
                    color: flameColor.withOpacity(_glowAnim.value * 0.5),
                    blurRadius: 16,
                    spreadRadius: -1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: flameColor.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.local_fire_department_rounded,
                color: flameColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.streak} DIAS',
                  style: TextStyle(
                    color: hasStreak ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  hasStreak
                      ? (widget.isActiveToday ? 'Ofensiva ativa!' : 'Pratique hoje!')
                      : 'Comece sua sequência',
                  style: TextStyle(
                    color: flameColor.withOpacity(0.9),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
