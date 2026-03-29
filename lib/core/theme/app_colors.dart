import 'package:flutter/material.dart';

/// Paleta de cores centralizada do Quiz Vance.
/// Nenhuma tela define cores diretamente — todas referenciam esta classe.
abstract class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0D0E14);
  static const Color surface = Color(0xFF16171F);
  static const Color surface2 = Color(0xFF1E2030);

  // Borders
  static const Color border = Color(0xFF2A2D3E);

  // Brand
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryLight = Color(0xFF9D97FF);
  static const Color primaryDark = Color(0xFF4B44CC);

  // Accent
  static const Color accent = Color(0xFFFF6B6B);

  // Semantic
  static const Color success = Color(0xFF4ECDC4);
  static const Color warning = Color(0xFFFF9F43);
  static const Color error = Color(0xFFFF4757);

  // Gamification
  static const Color xpGold = Color(0xFFFFE66D);
  static const Color streakOrange = Color(0xFFFF6B35);
  static const Color levelPurple = Color(0xFFAD48FF);

  // Text
  static const Color textPrimary = Color(0xFFF0F0FF);
  static const Color textSecondary = Color(0xFFBFC3D6);
  static const Color textMuted = Color(0xFF8B8FA8);
  static const Color textDisabled = Color(0xFF4A4E63);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF9D63FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFE66D), Color(0xFFFFB347)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF4ECDC4), Color(0xFF44CF6C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
