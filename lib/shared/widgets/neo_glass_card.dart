import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';

/// Card Glassmorphic de Alta Performance ("Vance Neo-Glass").
/// Oferece desfoque suave, bordas luminosas e feedback tátil refinado.
class NeoGlassCard extends StatefulWidget {
  const NeoGlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = 20.0,
    this.blurAmount = 10.0,
    this.borderGradient,
    this.backgroundColor,
    this.hasGlow = false,
    this.glowColor,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blurAmount;
  final Gradient? borderGradient;
  final Color? backgroundColor;
  final bool hasGlow;
  final Color? glowColor;
  final EdgeInsetsGeometry? margin;

  @override
  State<NeoGlassCard> createState() => _NeoGlassCardState();
}

class _NeoGlassCardState extends State<NeoGlassCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0,
      upperBound: 0.03,
    );
    _scale = Tween<double>(begin: 1, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap != null) {
      _ctrl.forward();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap != null) {
      _ctrl.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null) {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveGlow = widget.glowColor ?? AppColors.primary;
    final cardContent = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: widget.hasGlow
            ? [
                BoxShadow(
                  color: effectiveGlow.withOpacity(0.35),
                  blurRadius: 0,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: effectiveGlow.withOpacity(0.22),
                  blurRadius: 22,
                  spreadRadius: -2,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 0,
                  offset: const Offset(0, 3),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: widget.blurAmount,
            sigmaY: widget.blurAmount,
          ),
          child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color:
                  widget.backgroundColor ?? AppColors.surface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: widget.borderGradient == null
                    ? AppColors.border.withOpacity(0.85)
                    : effectiveGlow.withOpacity(0.45),
                width: 1.4,
              ),
              gradient: widget.borderGradient != null
                  ? LinearGradient(
                      colors: [
                        effectiveGlow.withOpacity(0.14),
                        AppColors.surface.withOpacity(0.92),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.onTap == null) {
      return cardContent;
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: cardContent,
      ),
    );
  }
}
