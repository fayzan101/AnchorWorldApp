import 'package:flutter/material.dart';

/// Anchor World brand tokens (community).
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFFBA0C2F);
  static const Color primaryDeep = Color(0xFF8B0A24);
  static const Color ink = Color(0xFF1A1214);
  static const Color body = Color(0xFF5C5356);
  static const Color surface = Color(0xFFFFF8F9);
  static const Color card = Color(0xFFFFFFFF);
  static const Color accentMint = Color(0xFF0CBA97);
  static const Color accentGold = Color(0xFFE8A838);
  static const Color danger = Color(0xFFD32F2F);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color mutedBorder = Color(0xFFE8E0E2);
  static const Color chipIdle = Color(0xFFF3EEEF);
  static const Color gradientPurple = Color(0xFF4B134F);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [gradientPurple, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient get heroOverlay => LinearGradient(
        colors: [
          Colors.black.withOpacity(0.55),
          Colors.black.withOpacity(0.25),
          primaryDeep.withOpacity(0.45),
        ],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      );

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: primary.withOpacity(0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
