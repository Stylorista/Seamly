import 'package:flutter/material.dart';

abstract final class SeamlyColors {
  static const ink = Color(0xFF1D1A1B);
  static const cream = Color(0xFFF8F4ED);
  static const paper = Color(0xFFFFFCF7);
  static const plum = Color(0xFF7B315D);
  static const berry = Color(0xFFB9547A);
  static const moss = Color(0xFF5F7150);
  static const gold = Color(0xFFC5964C);
  static const sand = Color(0xFFC6976D);
  static const sandText = Color(0xFFC18F68);
  static const navigationSurface = Color(0xFFF0EFED);
  static const navigationIdle = Color(0xFFAFAFAD);
}

ThemeData buildSeamlyTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: SeamlyColors.plum,
    brightness: Brightness.light,
    surface: SeamlyColors.paper,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme.copyWith(
      primary: SeamlyColors.plum,
      secondary: SeamlyColors.moss,
      tertiary: SeamlyColors.gold,
      surface: SeamlyColors.paper,
      onSurface: SeamlyColors.ink,
    ),
    scaffoldBackgroundColor: SeamlyColors.cream,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 42,
        height: 1.05,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.4,
        color: SeamlyColors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
      ),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: SeamlyColors.paper,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: SeamlyColors.ink.withValues(alpha: 0.08)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.72),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: SeamlyColors.ink.withValues(alpha: 0.10),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: SeamlyColors.plum, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
