import 'package:flutter/material.dart';

/// Paleta de cores centralizada do Quiz Vance.
/// Nenhuma tela define cores diretamente — todas referenciam esta classe.
abstract class AppColors {
  // Backgrounds - Modern Slate Dark Palette
  static const Color background = Color(0xFF0F172A);
  static const Color surface = Color(0xFF1E293B);
  static const Color surface2 = Color(0xFF334155);

  // Borders
  static const Color border = Color(0xFF334155);

  // Brand
  static const Color primary = Color(0xFF7C3AED);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color primaryDark = Color(0xFF5B21B6);

  // Accent
  static const Color accent = Color(0xFF06B6D4);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFF43F5E);

  // Gamification
  static const Color xpGold = Color(0xFFFFB800);
  static const Color streakOrange = Color(0xFFFF5722);
  static const Color levelPurple = Color(0xFF8B5CF6);

  // Text
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFCBD5E1);
  // Slate 400 preserves readable contrast on both background and surfaces.
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF334155);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFB800), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyberGradient = LinearGradient(
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fireGradient = LinearGradient(
    colors: [Color(0xFFFF5722), Color(0xFFEF4444)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
