import 'package:flutter/material.dart';

/// AniSphere brand tokens — the new visual identity.
///
/// Mark: the ∞ symbol merged with the letter A, painted with a
/// blue → indigo → violet → magenta gradient on a deep space-violet ground.
///
/// This is the single source of truth for the brand. The legacy [AppColors]
/// and [AppGradients] constants are re-pointed at these values so the whole
/// app inherits the new identity automatically.
class AniSphereBrand {
  AniSphereBrand._();

  // ── Primary Gradient Colors ──────────────────────────────────────────
  static const Color blue = Color(0xFF2B4EF5); // left lobe / start
  static const Color indigo = Color(0xFF5B3DF5); // mid gradient
  static const Color violet = Color(0xFF8B2CF5); // transition
  static const Color magenta = Color(0xFFC026D3); // right lobe / end

  // ── Backgrounds ──────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0D0B1A); // main dark background
  static const Color bgCard = Color(0xFF16122E); // card surface
  static const Color bgElevated = Color(0xFF1E1840); // elevated surfaces / sheets

  // ── Text ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF); // 60% white
  static const Color textTertiary = Color(0x55FFFFFF); // 33% white

  // ── Border / Divider ─────────────────────────────────────────────────
  static const Color borderSubtle = Color(0x385B3DF5); // indigo @ 22%
  static const Color borderActive = Color(0xFF5B3DF5);

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
    colors: [Color(0xFF1A0D3D), Color(0xFF0D0B1A), Color(0xFF1A0428)],
    stops: [0.0, 0.55, 1.0],
  );

  static const RadialGradient glowGradient = RadialGradient(
    colors: [Color(0x668B2CF5), Colors.transparent],
    radius: 0.8,
  );

  // ── Shadows ───────────────────────────────────────────────────────────
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: const Color(0xFF5B3DF5).withOpacity(0.18),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> logoGlow = [
    BoxShadow(
      color: const Color(0xFF8B2CF5).withOpacity(0.45),
      blurRadius: 40,
      spreadRadius: 8,
    ),
  ];
}
