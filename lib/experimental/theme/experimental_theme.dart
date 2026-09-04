import 'package:flutter/material.dart';

ThemeData buildExperimentalTheme({required String variant}) {
  final palette = ExperimentalPalette.resolve(variant);

  const scheme = ColorScheme.dark(
    brightness: Brightness.dark,
    primary: Color(0xFF4CD3FF),
    secondary: Color(0xFF6E8BFF),
    surface: Color(0xFF0E1C2C),
    error: Color(0xFFFF7A7A),
    onPrimary: Color(0xFF08131F),
    onSecondary: Color(0xFFE7F1FF),
    onSurface: Color(0xFFE7F1FF),
    onError: Color(0xFF08131F),
  );

  final adjustedScheme = scheme.copyWith(
    primary: palette.primary,
    secondary: palette.secondary,
    surface: palette.surface,
    error: palette.danger,
    onPrimary: palette.background,
    onSecondary: palette.text,
    onSurface: palette.text,
    onError: palette.background,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: adjustedScheme,
    scaffoldBackgroundColor: palette.background,
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        color: palette.text,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: palette.text,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: palette.text,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: palette.text,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.45,
        color: palette.text,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.45,
        color: palette.muted,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: palette.text,
      ),
    ),
    cardTheme: CardTheme(
      color: palette.card,
      shadowColor: Colors.black54,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: palette.text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 78,
      backgroundColor: palette.panel,
      surfaceTintColor: Colors.transparent,
      indicatorColor: palette.primary.withOpacity(0.14),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? palette.primary : palette.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? palette.primary : palette.muted,
          size: 24,
        );
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surfaceAlt,
      disabledColor: palette.surfaceAlt,
      selectedColor: palette.primary.withOpacity(0.18),
      secondarySelectedColor: palette.primary.withOpacity(0.18),
      side: BorderSide(color: Colors.white.withOpacity(0.06)),
      labelStyle: TextStyle(
        color: palette.text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    ),
    dividerColor: Colors.white.withOpacity(0.08),
    extensions: <ThemeExtension<dynamic>>[
      ExperimentalColors(
        background: palette.background,
        surface: palette.surface,
        surfaceAlt: palette.surfaceAlt,
        panel: palette.panel,
        card: palette.card,
        text: palette.text,
        muted: palette.muted,
        primary: palette.primary,
        secondary: palette.secondary,
        accent: palette.accent,
        success: palette.success,
        danger: palette.danger,
      ),
    ],
  );
}

class ExperimentalPalette {
  const ExperimentalPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.panel,
    required this.card,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.success,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color panel;
  final Color card;
  final Color text;
  final Color muted;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color success;
  final Color danger;

  static ExperimentalPalette resolve(String variant) {
    switch (variant) {
      case '1':
        return const ExperimentalPalette(
          background: Color(0xFF16181D),
          surface: Color(0xFF1E2228),
          surfaceAlt: Color(0xFF272D34),
          panel: Color(0xFF1B2026),
          card: Color(0xFF232930),
          text: Color(0xFFF2ECE1),
          muted: Color(0xFFB6AC9A),
          primary: Color(0xFFD9C29A),
          secondary: Color(0xFF8EA0B8),
          accent: Color(0xFFE0B35B),
          success: Color(0xFF5EC7A3),
          danger: Color(0xFFFF8A7A),
        );
      case '2':
        return const ExperimentalPalette(
          background: Color(0xFFF4EFE7),
          surface: Color(0xFFF8F4ED),
          surfaceAlt: Color(0xFFE7DED1),
          panel: Color(0xFFFFFCF8),
          card: Color(0xFFFFFAF4),
          text: Color(0xFF22262D),
          muted: Color(0xFF6E727A),
          primary: Color(0xFFC26E3D),
          secondary: Color(0xFF363F4E),
          accent: Color(0xFFD99962),
          success: Color(0xFF2F8F74),
          danger: Color(0xFFC95F5F),
        );
      case '4':
        return const ExperimentalPalette(
          background: Color(0xFFEEF1F4),
          surface: Color(0xFFF5F7FA),
          surfaceAlt: Color(0xFFE1E7EE),
          panel: Color(0xFFFFFFFF),
          card: Color(0xFFF9FBFD),
          text: Color(0xFF1C2430),
          muted: Color(0xFF687181),
          primary: Color(0xFF4E637D),
          secondary: Color(0xFF8795AA),
          accent: Color(0xFF9AA6B7),
          success: Color(0xFF2F8B78),
          danger: Color(0xFFC96464),
        );
      case 'tech':
      default:
        return const ExperimentalPalette(
          background: Color(0xFF08131F),
          surface: Color(0xFF0E1C2C),
          surfaceAlt: Color(0xFF13263A),
          panel: Color(0xFF122234),
          card: Color(0xFF172B41),
          text: Color(0xFFE7F1FF),
          muted: Color(0xFF91A6BF),
          primary: Color(0xFF4CD3FF),
          secondary: Color(0xFF6E8BFF),
          accent: Color(0xFFFF9F5A),
          success: Color(0xFF34D399),
          danger: Color(0xFFFF7A7A),
        );
    }
  }
}

@immutable
class ExperimentalColors extends ThemeExtension<ExperimentalColors> {
  const ExperimentalColors({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.panel,
    required this.card,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.success,
    required this.danger,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color panel;
  final Color card;
  final Color text;
  final Color muted;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color success;
  final Color danger;

  @override
  ExperimentalColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? panel,
    Color? card,
    Color? text,
    Color? muted,
    Color? primary,
    Color? secondary,
    Color? accent,
    Color? success,
    Color? danger,
  }) {
    return ExperimentalColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      panel: panel ?? this.panel,
      card: card ?? this.card,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      danger: danger ?? this.danger,
    );
  }

  @override
  ExperimentalColors lerp(
    ThemeExtension<ExperimentalColors>? other,
    double t,
  ) {
    if (other is! ExperimentalColors) {
      return this;
    }
    return ExperimentalColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      card: Color.lerp(card, other.card, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}
