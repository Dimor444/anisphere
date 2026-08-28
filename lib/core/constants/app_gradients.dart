import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/brand.dart';
import 'app_colors.dart';

/// Reusable gradients. AniSphere never uses flat grey placeholders —
/// every surface that would otherwise be empty gets an anime-colored gradient.
class AppGradients {
  AppGradients._();

  /// The signature brand fill — now FLAT (#1DB367 at every stop).
  ///
  /// Deliberately still a 4-stop LinearGradient: type and stop count are
  /// preserved so the 44 call sites that pass or index into it keep working,
  /// and every consumer renders flat without being touched individually.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AniSphereBrand.indigo,
      AniSphereBrand.indigo,
      AniSphereBrand.indigo,
      AniSphereBrand.indigo,
    ],
    stops: [0.0, 0.38, 0.70, 1.0],
  );

  static const LinearGradient brandTri = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    // FLAT — 3 stops kept.
    colors: [AniSphereBrand.indigo, AniSphereBrand.indigo, AniSphereBrand.indigo],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient purpleCyan = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    // FLAT — 2 stops kept.
    colors: [AppColors.primary, AppColors.primary],
  );

  static const LinearGradient purpleDeep = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );

  static const LinearGradient gold = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.aniGoldBright, AppColors.aniGoldDeep],
  );

  static const RadialGradient goldRadial = RadialGradient(
    colors: [AppColors.aniGoldBright, AppColors.aniGoldDeep],
    radius: 0.85,
  );

  static const LinearGradient gem = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.aniGem, Color(0xFF15803D), AppColors.aniGemDeep],
    stops: [0.0, 0.55, 1.0],
  );

  /// Default screen background — deep space-violet, matching the brand ground.
  static const LinearGradient pageBg = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A2415), AppColors.background, Color(0xFF06200F)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Soft radial brand glow for hero/empty areas.
  static const RadialGradient glow = AniSphereBrand.glowGradient;

  /// A curated set of two-color gradients used to give each anime / avatar a
  /// distinct, vivid identity. Picked deterministically from a seed string.
  static const List<List<Color>> palette = [
    [Color(0xFFF59E0B), Color(0xFFF97316)], // amber → orange
    [Color(0xFFBE123C), Color(0xFFE11D48)], // deep rose → rose
    [Color(0xFF0F766E), Color(0xFF115E56)], // pine teal → dark pine
    [Color(0xFFFBBF24), Color(0xFFF59E0B)], // gold → amber
    [Color(0xFFC2410C), Color(0xFFB03A08)], // rust → deep rust
    [Color(0xFF2DD4BF), Color(0xFF14B8A6)], // aqua → teal
    [Color(0xFFBE185D), Color(0xFFDB2777)], // wine pink → deep pink
    [Color(0xFFFCD34D), Color(0xFFF59E0B)], // sand → amber
    [Color(0xFF22D3EE), Color(0xFF0891B2)], // cyan → deep cyan
    [Color(0xFFFDA4AF), Color(0xFFFB7185)], // blush → coral
    [Color(0xFFFBBF24), Color(0xFFEA580C)], // gold → tangerine
    [Color(0xFF5EEAD4), Color(0xFF0D9488)], // mint → deep teal
  ];

  /// Deterministic gradient for a given key (anime title, username, etc.).
  static LinearGradient forSeed(String seed, {double angle = 135}) {
    final pair = pairForSeed(seed);
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: pair,
    );
  }

  static List<Color> pairForSeed(String seed) {
    if (seed.isEmpty) return palette.first;
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  // ── Readable foreground ──────────────────────────────────────────────
  //
  // The palette is warm and light, so a single hardcoded foreground cannot
  // work: white fails on the ambers, near-black fails on the deep teals.
  // These pick per-fill instead, so every caller gets the legible one
  // without hardcoding a colour.

  /// Relative luminance per WCAG 2.1. Channels are already 0..1 here, which
  /// is the same value the spec's `c / 255` produces.
  static double _luminance(Color c) {
    double channel(double s) =>
        s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  /// Foreground that reads on a solid [bg].
  ///
  /// The 0.35 threshold is deliberately above the 0.179 midpoint that
  /// maximises the *worse* of the two contrasts. Sitting higher keeps white
  /// on mid-tone fills, where white is the safer of two imperfect options
  /// and matches the rest of the dark UI.
  static Color onFill(Color bg) {
    // The brand's own colour is special-cased rather than nudging the
    // threshold, which is correct for all 12 palette pairs. #1DB367 has a
    // luminance of 0.3348 — 0.0152 BELOW the cutoff — so the generic rule
    // would pick white at 2.73 (fail) when onBrand gives 6.84 (pass).
    if (bg.toARGB32() == AppColors.primary.toARGB32()) return AppColors.onBrand;
    return _luminance(bg) > 0.35 ? AppColors.onBrand : Colors.white;
  }

  /// Foreground for a gradient. Text spans the whole fill rather than sitting
  /// on one stop, so this averages the stops' luminance instead of testing
  /// either end. Falls back to white on an empty list.
  ///
  /// FRAGILITY — every [palette] pair currently clears WCAG AA (>= 4.5) for
  /// the foreground picked here, but two sit right on the edge:
  ///
  ///   pair 1  amber → orange     (#F59E0B/#F97316)  mean 0.382
  ///   pair 9  cyan → deep cyan   (#22D3EE/#0891B2)  mean 0.383
  ///
  /// Both are only ~0.03 ABOVE the 0.35 threshold, so they pick onBrand and
  /// pass. Lighten either one enough to cross back under 0.35 and it silently
  /// flips to white, landing at 2.15 and 1.81 respectively — a failure with no
  /// compile-time signal. If you touch those two stops, re-run the contrast
  /// check before shipping. Every other pair has >= 0.06 of margin.
  ///
  /// A third case sits on the WRONG side of the line already: the flat brand
  /// AppColors.primary (#1DB367) has luminance 0.3348, just under 0.35, so the
  /// generic rule would pick white at 2.73. [onFill] special-cases it back to
  /// onBrand (6.84). [onGradient] does NOT — a gradient whose stops average out
  /// near the brand colour will still pick white. No caller does that today
  /// (all five pass palette pairs), but it is the trap to watch.
  static Color onGradient(List<Color> colors) {
    if (colors.isEmpty) return Colors.white;
    final mean =
        colors.map(_luminance).reduce((a, b) => a + b) / colors.length;
    return mean > 0.35 ? AppColors.onBrand : Colors.white;
  }
}
