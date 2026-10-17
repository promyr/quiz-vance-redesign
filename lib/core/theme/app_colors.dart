import 'package:flutter/material.dart';

/// Paleta de cores centralizada do Quiz Vance.
/// Nenhuma tela define cores diretamente — todas referenciam esta classe.
abstract class AppColors {
  // Backgrounds — Deep Obsidian Gamified Palette (Brilliant / Duolingo Dark style)
  static const Color background = Color(0xFF0A0E17);
  static const Color surface = Color(0xFF131B2E);
  static const Color surface2 = Color(0xFF1D2842);

  // Borders — Crisp structural & tactile lip borders
  static const Color border = Color(0xFF283756);

  // Brand — Electric Cobalt & Luminous Sky (replaces tiring #7C3AED purple)
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color primaryDark = Color(0xFF1D4ED8);

  // Accent — Vibrant Cyber Mint
  static const Color accent = Color(0xFF00E5A3);

  // Semantic — High-contrast gamified feedback
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFF43F5E);

  // Gamification
  static const Color xpGold = Color(0xFFFFC800);
  static const Color streakOrange = Color(0xFFFF6B00);
  static const Color levelPurple = Color(0xFF6366F1);

  // Text
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFFD1D9E6);
  // High-legibility cool grey on both background and tactile surfaces.
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFF334155);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFC800), Color(0xFFF59E0B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF22C55E), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyberGradient = LinearGradient(
    colors: [Color(0xFF00E5A3), Color(0xFF3B82F6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fireGradient = LinearGradient(
    colors: [Color(0xFFFF6B00), Color(0xFFF43F5E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0xFF182238), Color(0xFF111827)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient neonPurpleGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF38BDF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient electricCyanGradient = LinearGradient(
    colors: [Color(0xFF00E5A3), Color(0xFF38BDF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Glassmorphism & Tactile tokens
  static const Color glassBackground = Color(0x33131B2E);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color glassHighlight = Color(0x1AFFFFFF);
}
