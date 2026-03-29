/// Toast de conquista/level-up — overlay animado que aparece no topo da tela.
///
/// Uso:
/// ```dart
/// AchievementToast.showAchievement(context, name: '🏆 Dedicado', xp: 500);
/// AchievementToast.showLevelUp(context, level: 5);
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

// ── Entrada pública ────────────────────────────────────────────────────────

abstract class AchievementToast {
  /// Exibe o toast de nova conquista desbloqueada.
  static void showAchievement(
    BuildContext context, {
    required String name,
    int xp = 0,
  }) {
    _show(
      context,
      _ToastData(
        icon: '🏆',
        topLabel: 'CONQUISTA DESBLOQUEADA',
        mainText: name,
        bottomLabel: xp > 0 ? '+$xp XP' : null,
        gradientColors: const [Color(0xFFF59E0B), Color(0xFFD97706)],
      ),
    );
  }

  /// Exibe o toast de level-up.
  static void showLevelUp(BuildContext context, {required int level}) {
    _show(
      context,
      _ToastData(
        icon: '⚡',
        topLabel: 'LEVEL UP!',
        mainText: 'Você alcançou o nível $level',
        bottomLabel: null,
        gradientColors: [AppColors.primary, const Color(0xFF6D28D9)],
      ),
    );
  }

  static void _show(BuildContext context, _ToastData data) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        data: data,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

// ── Dados internos ─────────────────────────────────────────────────────────

class _ToastData {
  const _ToastData({
    required this.icon,
    required this.topLabel,
    required this.mainText,
    required this.gradientColors,
    this.bottomLabel,
  });

  final String icon;
  final String topLabel;
  final String mainText;
  final String? bottomLabel;
  final List<Color> gradientColors;
}

// ── Widget de overlay ──────────────────────────────────────────────────────

class _ToastOverlay extends StatefulWidget {
  const _ToastOverlay({required this.data, required this.onDismiss});

  final _ToastData data;
  final VoidCallback onDismiss;

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideY;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _slideY = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _ctrl.forward();

    // Auto-dismiss depois de 3.5 segundos
    Future.delayed(const Duration(milliseconds: 3500), _dismiss);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => FractionalTranslation(
          translation: Offset(0, _slideY.value),
          child: Opacity(opacity: _opacity.value, child: child),
        ),
        child: GestureDetector(
          onTap: _dismiss,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.data.gradientColors,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: widget.data.gradientColors.first.withOpacity(0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Emoji com fundo circular
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.data.icon,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.forward())
                      .scale(
                        duration: 400.ms,
                        delay: 150.ms,
                        curve: Curves.elasticOut,
                      ),

                  const SizedBox(width: 12),

                  // Textos
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.data.topLabel,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.data.mainText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.data.bottomLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.data.bottomLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Ícone de fechar
                  Icon(
                    Icons.close_rounded,
                    color: Colors.white.withOpacity(0.7),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
