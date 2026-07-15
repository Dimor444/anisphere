import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_fonts.dart';

/// Typography: Outfit for UI text, Space Grotesk for numbers/stats.
/// Fonts are bundled (see `assets/fonts/`) — no runtime network fetch.
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle display = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.textPrimary,
    height: 1.1,
  );

  static const TextStyle heading = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle subheading = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );

  static const TextStyle captionMuted = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static const TextStyle label = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// Numbers, counters, currency amounts.
  static const TextStyle numbers = TextStyle(
    fontFamily: AppFonts.spaceGrotesk,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle numbersLg({Color? color}) => TextStyle(
        fontFamily: AppFonts.spaceGrotesk,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
      );

  static TextStyle numbersXl({Color? color}) => TextStyle(
        fontFamily: AppFonts.spaceGrotesk,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textPrimary,
      );

  /// Gradient brand wordmark style (apply with a ShaderMask).
  static const TextStyle wordmark = TextStyle(
    fontFamily: AppFonts.outfit,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: 0.2,
  );
}
