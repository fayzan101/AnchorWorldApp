import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle display(double size, {Color? color, FontWeight weight = FontWeight.w700}) {
    return GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      height: 1.15,
    );
  }

  static TextStyle ui({
    double size = 14,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double height = 1.35,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.ink,
      height: height,
    );
  }

  static TextStyle get heroBrand => display(42, color: AppColors.white, weight: FontWeight.w800);

  static TextStyle get screenTitle => display(28, weight: FontWeight.w700);

  static TextStyle get sectionTitle => ui(size: 18, weight: FontWeight.w700);

  static TextStyle get body => ui(size: 15, color: AppColors.body);

  static TextStyle get caption => ui(size: 13, color: AppColors.body, weight: FontWeight.w500);

  static TextStyle get button => ui(size: 16, color: AppColors.white, weight: FontWeight.w700);
}
