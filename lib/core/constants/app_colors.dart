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
  static const Color primary = AniSphereBrand.indigo; // brand emerald
  static const Color primaryLight = Color(0xFF7FD9A8); // light emerald (active states)
  static const Color primaryDark = Color(0xFF0A5C3C); // deep emerald
  static const Color secondary = AniSphereBrand.magenta; // gradient end
  static const Color accent = AniSphereBrand.blue; // gradient start (blue lobe)
  /// Foreground for content sitting ON a brand gradient/fill. The emerald
  /// family is light enough that white no longer contrasts against most of
  /// it — this near-black reads instead. Only valid over the LIGHT end of
  /// the brand ramp; it does not read on dark or translucent surfaces.
  static const Color onBrand = Color(0xFF04160C);

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
  static const Color border = Color(0xFF1F3A2C); // subtle green-tinted border
  static const Color verified = Color(0xFF1D9BF0); // verification blue

  // Glass — GlassSurface's fills and edge. Both of its modes use the same
  // tokens, so a surface looks the same blurred or tinted over the flat page:
  // choosing a mode is a cost decision, not a look. Neutral on purpose — no
  // brand tint and no light (37eccd6 took the brand's glow out of the app).
  // Nothing adopts these yet.

  /// The card surface (bgCard #0E1A14) at 72%. Over the page background it
  /// composites to within 3 levels per channel of today's opaque card, so
  /// moving a card onto glass changes nothing on the flat page, while the 28%
  /// lets artwork behind it show through. The value the blur was measured at.
  static const Color glassFill = Color(0xB80E1A14);

  /// bgCard at 88% — for dense text over busy content: sheets, dialogs.
  static const Color glassFillStrong = Color(0xE00E1A14);

  /// White at 10% — the hairline edge. The solid [border] is a line painted
  /// on an opaque card; over a translucent surface a translucent edge reads
  /// as the rim of the material, where an opaque green one looks drawn on.
  static const Color glassBorder = Color(0x1AFFFFFF);

  // Aura glow colors (per level)
  static const Color glowWhite = Color(0xFFE5E7EB);
  static const Color glowBlue = Color(0xFF3B82F6);
  static const Color glowOrange = Color(0xFFF97316);
  static const Color glowPurple = Color(0xFFA855F7);
  static const Color glowGold = Color(0xFFFACC15);
}
