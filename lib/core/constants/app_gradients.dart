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
    colors: [Color(0xFF1A0D3D), AppColors.background, Color(0xFF1A0428)],
    stops: [0.0, 0.55, 1.0],
  );

  /// Soft radial brand glow for hero/empty areas.
  static const RadialGradient glow = AniSphereBrand.glowGradient;

  /// A curated set of two-color gradients used to give each anime / avatar a
  /// distinct, vivid identity. Picked deterministically from a seed string.
  static const List<List<Color>> palette = [
    [Color(0xFF2B4EF5), Color(0xFF8B2CF5)], // blue → violet
    [Color(0xFF5B3DF5), Color(0xFFC026D3)], // indigo → magenta
    [Color(0xFF3B82F6), Color(0xFF5B3DF5)], // sky → indigo
    [Color(0xFF8B2CF5), Color(0xFFEC4899)], // violet → pink
    [Color(0xFF2B4EF5), Color(0xFF5B3DF5)], // blue → indigo
    [Color(0xFF7C3AED), Color(0xFFC026D3)], // purple → magenta
    [Color(0xFF6366F1), Color(0xFF8B2CF5)], // indigo → violet
    [Color(0xFF5B3DF5), Color(0xFF22D3EE)], // indigo → cyan pop
    [Color(0xFFA855F7), Color(0xFFC026D3)], // orchid → magenta
    [Color(0xFF2B4EF5), Color(0xFFC026D3)], // blue → magenta (full)
    [Color(0xFF4F46E5), Color(0xFF9333EA)], // indigo → purple
    [Color(0xFF8B2CF5), Color(0xFFC026D3)], // violet → magenta
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
