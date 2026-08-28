import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF7C5CFF);

  static ThemeData dark() => _base(Brightness.dark).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF12101C),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF12101C),
          elevation: 0,
          centerTitle: false,
        ),
      );

  static ThemeData light() => _base(Brightness.light).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
      );

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Roboto',
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
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
    );
  }
}

const List<Color> genreGradients = [
  Color(0xFF7C5CFF),
  Color(0xFF00B8A9),
  Color(0xFFFF6B6B),
  Color(0xFFF7B267),
  Color(0xFF5BB8FF),
  Color(0xFF9B5DE5),
];