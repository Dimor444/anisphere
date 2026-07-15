import 'package:flutter/material.dart';
import '../theme/brand.dart';

/// AniSphere brand palette — dark theme only.
///
/// Brand-family slots are re-pointed at [AniSphereBrand] (the new
/// blue→indigo→violet→magenta identity). Functional colors (currencies,
/// status, auras) are deliberately left independent.
class AppColors {
  AppColors._();

  // Surfaces
  static const Color background = AniSphereBrand.bgDark; // deep space violet
  static const Color surface = AniSphereBrand.bgCard; // card background
  static const Color surfaceAlt = AniSphereBrand.bgElevated; // elevated surface

  // Brand
  static const Color primary = AniSphereBrand.indigo; // brand indigo
  static const Color primaryLight = Color(0xFFB794F6); // light violet (active states)
  static const Color primaryDark = Color(0xFF3B27B8); // deep indigo
  static const Color secondary = AniSphereBrand.magenta; // gradient end
  static const Color accent = AniSphereBrand.blue; // gradient start (blue lobe)

  // Currencies
  static const Color aniGold = Color(0xFFF59E0B); // AniGold
  static const Color aniGoldBright = Color(0xFFFFD700);
  static const Color aniGoldDeep = Color(0xFFB8860B);
  static const Color aniGem = Color(0xFF10B981); // AniGem
  static const Color aniGemDeep = Color(0xFF166534);

  // Status
  static const Color success = Color(0xFF22C55E); // correct answer
  static const Color error = Color(0xFFEF4444); // wrong answer
  static const Color warning = Color(0xFFF97316);
  static const Color streak = Color(0xFFFB7185);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3B8D4);
  static const Color textMuted = Color(0xFF6B7280);

  // Lines / accents
  static const Color border = Color(0xFF2A2350); // subtle indigo-tinted border
  static const Color verified = Color(0xFF1D9BF0); // verification blue

  // Aura glow colors (per level)
  static const Color glowWhite = Color(0xFFE5E7EB);
  static const Color glowBlue = Color(0xFF3B82F6);
  static const Color glowOrange = Color(0xFFF97316);
  static const Color glowPurple = Color(0xFFA855F7);
  static const Color glowGold = Color(0xFFFACC15);
}
