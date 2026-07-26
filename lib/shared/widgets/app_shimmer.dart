import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';

class AppShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const AppShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ).animate(onPlay: (controller) => controller.repeat()).shimmer(
          duration: 1200.ms,
          color: AppColors.border.withOpacity(0.5),
        );
  }
}

class AppShimmerCard extends StatelessWidget {
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const AppShimmerCard({
    super.key,
    this.height = 100.0,
    this.borderRadius = 16.0,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          AppShimmer(width: 140, height: 14, borderRadius: 6),
          SizedBox(height: 10),
          AppShimmer(width: double.infinity, height: 10, borderRadius: 4),
          SizedBox(height: 6),
          AppShimmer(width: 200, height: 10, borderRadius: 4),
        ],
      ),
    );
  }
}
