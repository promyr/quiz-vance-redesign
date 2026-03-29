import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';

/// Barra de progresso animada com gradiente.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.gradient,
    this.backgroundColor,
    this.borderRadius,
  }) : assert(value >= 0 && value <= 1);

  final double value;
  final double height;
  final Gradient? gradient;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(height / 2);
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          // Background
          Container(
            height: height,
            color: backgroundColor ?? AppColors.surface2,
          ),
          // Fill
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: gradient ?? AppColors.primaryGradient,
              ),
            ),
          ).animate().scaleX(
                begin: 0,
                end: 1,
                alignment: Alignment.centerLeft,
                duration: 600.ms,
                curve: Curves.easeOutCubic,
              ),
        ],
      ),
    );
  }
}
