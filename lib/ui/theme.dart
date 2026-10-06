import 'dart:ui';

import 'package:flutter/material.dart';

/// Brand identity: "Ink & Ember".
///
/// A warm, literary palette — deep ink-black plum surfaces warmed by burnished
/// bronze ("the spark of a story beginning"), aged-leather secondary and a
/// rust/ember red for mature or destructive moments. Deliberately not the
/// cool lavender-blue that most AI apps default to.
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFFC8956C); // burnished bronze
  static const _bgDark = Color(0xFF0C0A0F); // ink
  static const _bgLight = Color(0xFFFAF5EC); // parchment
  static const _surfaceDark = Color(0xFF171320); // warm plum
  static const _surfaceLight = Color(0xFFFFFFFF);

  static const _secondary = Color(0xFF8B6F4A); // aged leather
  static const _tertiary = Color(0xFFB85A44); // ember / rust

  static ThemeData dark() => _base(Brightness.dark).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
          surface: _surfaceDark,
          secondary: _secondary,
          tertiary: _tertiary,
        ),
        scaffoldBackgroundColor: _bgDark,
      );

  static ThemeData light() => _base(Brightness.light).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B5E3C), // bronze, darkened for contrast
          brightness: Brightness.light,
          surface: _surfaceLight,
          secondary: _secondary,
          tertiary: _tertiary,
        ),
        scaffoldBackgroundColor: _bgLight,
      );

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      secondary: _secondary,
      tertiary: _tertiary,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
      scaffoldBackgroundColor: isDark ? _bgDark : _bgLight,
      // Editorial typographic hierarchy — tight tracking on labels, heavy
      // display weights, generous body leading.
      textTheme: (isDark ? Typography.blackMountainView : Typography.blackMountainView)
          .apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: isDark ? _surfaceDark : _surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.3 : 0.55),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        labelStyle: TextStyle(
            color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        floatingLabelStyle: TextStyle(
            color: scheme.primary, fontWeight: FontWeight.w700),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.6)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: const ChipThemeData(),
      tabBarTheme: TabBarThemeData(
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.3),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: scheme.onSurfaceVariant),
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 3, color: AppTheme.seed),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? _surfaceDark : _surfaceLight,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? _surfaceDark : _surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF221C2E) : Colors.white,
        contentTextStyle: TextStyle(color: isDark ? scheme.onSurface : Colors.black),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(),
    );
  }
}

const List<Color> genreGradients = [
  Color(0xFFC8956C), // bronze
  Color(0xFF0F8E7D), // deep teal
  Color(0xFFC44536), // ember red
  Color(0xFFB98A2E), // gilded
  Color(0xFF3E6EA5), // slate blue
  Color(0xFF6E4F9E), // amethyst
  Color(0xFFB0486B), // mulberry
  Color(0xFF4E8C5A), // moss
];

/// Soft outer glow used behind hero cards and covers.
BoxDecoration glowCard(Color base) => BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: base.withValues(alpha: 0.3),
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
