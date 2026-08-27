import 'package:flutter/material.dart';
import '../theme/brand.dart';
import 'app_colors.dart';

/// Reusable gradients. AniSphere never uses flat grey placeholders —
/// every surface that would otherwise be empty gets an anime-colored gradient.
class AppGradients {
  AppGradients._();

  /// The signature logo gradient: blue → indigo → violet → magenta.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AniSphereBrand.blue,
      AniSphereBrand.indigo,
      AniSphereBrand.violet,
      AniSphereBrand.magenta,
    ],
    stops: [0.0, 0.38, 0.70, 1.0],
  );

  static const LinearGradient brandTri = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AniSphereBrand.blue, AniSphereBrand.violet, AniSphereBrand.magenta],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient purpleCyan = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.accent],
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

}
