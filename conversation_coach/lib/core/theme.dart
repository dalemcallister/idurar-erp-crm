import 'package:flutter/material.dart';

/// App theme. Coaching language is warm and constructive (Design principle 5),
/// so the palette is calm and editorial rather than a clinical dashboard.
class CoachTheme {
  static const seed = Color(0xFF2E6F6A); // muted teal

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F5F1),
      appBarTheme: const AppBarTheme(centerTitle: false),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
      ),
      chipTheme: const ChipThemeData(side: BorderSide.none),
    );
  }

  /// Colour for a 0–100 score (red → amber → green).
  static Color scoreColor(double score) {
    if (score >= 75) return const Color(0xFF2E7D5B);
    if (score >= 50) return const Color(0xFFB8860B);
    return const Color(0xFFB44A3F);
  }
}
