import 'dart:ui';

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF8B78FF);
  static const _bgDark = Color(0xFF0E0C16);
  static const _surfaceDark = Color(0xFF171422);

  static ThemeData dark() => _base(Brightness.dark).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: _surfaceDark,
        ),
        scaffoldBackgroundColor: _bgDark,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
      );

  static ThemeData light() => _base(Brightness.light).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          scrolledUnderElevation: 0,
        ),
      );

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor:
          isDark ? _bgDark : const Color(0xFFFAF9FF),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: isDark ? _surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.5),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: const ChipThemeData(),
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

const List<Color> genreGradients = [
  Color(0xFF8B78FF),
  Color(0xFF00B8A9),
  Color(0xFFFF6B6B),
  Color(0xFFF7B267),
  Color(0xFF5BB8FF),
  Color(0xFFB78CFF),
  Color(0xFFFF8FB1),
  Color(0xFF4ED8C3),
];

/// Soft outer glow used behind hero cards and covers.
BoxDecoration glowCard(Color base) => BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: base.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );

/// Blurred backdrop layer for covers (frosted-glass feel).
Widget backdropBlur({required Widget child, double sigma = 0.001}) => ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );