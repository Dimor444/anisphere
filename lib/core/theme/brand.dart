import 'package:flutter/material.dart';

/// AniSphere brand tokens — the new visual identity.
///
/// Mark: the ∞ symbol merged with the letter A, painted with a
/// deep-emerald → emerald → radiant-green gradient on a deep green-black
/// ground. NOTE: the `blue`/`indigo`/`violet`/`magenta` identifiers below
/// keep their legacy names — they now hold green values.
///
/// This is the single source of truth for the brand. The legacy [AppColors]
/// and [AppGradients] constants are re-pointed at these values so the whole
/// app inherits the new identity automatically.
class AniSphereBrand {
  AniSphereBrand._();

  // ── Primary Gradient Colors ──────────────────────────────────────────
  static const Color blue = Color(0xFF137A52); // left lobe / start
  static const Color indigo = Color(0xFF1DB367); // mid gradient
  static const Color violet = Color(0xFF25C270); // transition
  static const Color magenta = Color(0xFF34D17F); // right lobe / end

  // ── Backgrounds ──────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF04160C); // main dark background
  static const Color bgCard = Color(0xFF0E1A14); // card surface
  static const Color bgElevated = Color(0xFF16281E); // elevated surfaces / sheets

  // ── Text ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF); // 60% white
  static const Color textTertiary = Color(0x55FFFFFF); // 33% white

  // ── Border / Divider ─────────────────────────────────────────────────
  static const Color borderSubtle = Color(0x381DB367); // emerald @ 22%
  static const Color borderActive = Color(0xFF1DB367);

  // ── Gradients ────────────────────────────────────────────────────────
  static const LinearGradient logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blue, indigo, violet, magenta],
    stops: [0.0, 0.38, 0.70, 1.0],
  );

  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0A2415), Color(0xFF04160C), Color(0xFF06200F)],
    stops: [0.0, 0.55, 1.0],
  );

  static const RadialGradient glowGradient = RadialGradient(
    colors: [Color(0x6625C270), Colors.transparent],
    radius: 0.8,
  );

  // ── Shadows ───────────────────────────────────────────────────────────
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF1DB367).withOpacity(0.18),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> logoGlow = [
    BoxShadow(
      color: const Color(0xFF25C270).withOpacity(0.45),
      blurRadius: 40,
      spreadRadius: 8,
    ),
  ];
}
