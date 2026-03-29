import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';

/// Caixa de esqueleto com animação de pulso (fade) para estados de carregamento.
///
/// Usa [flutter_animate] que já está no projeto — sem dependências extras.
///
/// Uso básico:
/// ```dart
/// SkeletonBox(width: 120, height: 14, radius: 6)
/// ```
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(
          duration: 700.ms,
          curve: Curves.easeInOut,
          begin: 0.4,
        );
  }
}

/// Skeleton de um ModeCard — mesmas dimensões e padding do widget real.
class ModeCardSkeleton extends StatelessWidget {
  const ModeCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          // emoji placeholder
          SkeletonBox(width: 32, height: 32, radius: 6),
          SizedBox(height: 10),
          // título
          SkeletonBox(width: 72, height: 11),
          SizedBox(height: 6),
          // descrição linha 1
          SkeletonBox(height: 9),
          SizedBox(height: 4),
          // descrição linha 2 (mais curta)
          SkeletonBox(width: 60, height: 9),
        ],
      ),
    );
  }
}

/// Skeleton de um StatTile (grade de 3 tiles no perfil).
class StatTileSkeleton extends StatelessWidget {
  const StatTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SkeletonBox(width: 40, height: 20, radius: 6),
          SizedBox(height: 8),
          SkeletonBox(width: 52, height: 10),
        ],
      ),
    );
  }
}

/// Skeleton do cabeçalho do perfil: avatar + nome + badge de plano.
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // avatar circular
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 2),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(duration: 700.ms, curve: Curves.easeInOut, begin: 0.4),
        const SizedBox(height: 12),
        const SkeletonBox(width: 120, height: 16, radius: 8),
        const SizedBox(height: 8),
        const SkeletonBox(width: 80, height: 12, radius: 6),
      ],
    );
  }
}
