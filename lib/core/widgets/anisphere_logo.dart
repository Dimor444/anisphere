import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/brand.dart';

/// The AniSphere logo mark — infinity (∞) merged with the letter A.
/// Use [size] to scale. Use [showWordmark] to include "AniSphere" text below.
class AniSphereLogo extends StatelessWidget {
  final double size;
  final bool showWordmark;

  const AniSphereLogo({super.key, this.size = 80, this.showWordmark = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: SvgPicture.string(
            _logoSvg,
            width: size,
            height: size,
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(height: 12),
          _Wordmark(width: size * 2.4),
        ],
      ],
    );
  }

  // SVG faithful to the logo: infinity ribbon (left lobe = C-shape + A peak, right lobe = oval)
  //
  // NOTE: the stop-colors below DUPLICATE AniSphereBrand.logoGradient rather
  // than referencing it (flutter_svg parses a raw string, so the Dart tokens
  // cannot be interpolated as-is). Both must be updated together — a brand
  // token swap does NOT reach this glyph on its own.
  static const String _logoSvg = '''
<svg viewBox="0 0 240 180" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="lg" x1="0" y1="0" x2="240" y2="130" gradientUnits="userSpaceOnUse">
      <stop offset="0%"   stop-color="#1DB367"/>
      <stop offset="38%"  stop-color="#1DB367"/>
      <stop offset="70%"  stop-color="#1DB367"/>
      <stop offset="100%" stop-color="#1DB367"/>
    </linearGradient>
    <filter id="glow">
      <feGaussianBlur in="SourceGraphic" stdDeviation="4" result="blur"/>
      <feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>

  <!-- Left lobe of ∞ (C-shape) -->
  <path d="M 120 65 C 105 30, 55 20, 35 52 C 15 84, 28 124, 68 130 C 90 135, 110 118, 120 100"
        stroke="url(#lg)" stroke-width="22" stroke-linecap="round" fill="none"/>

  <!-- Right lobe of ∞ (oval loop) -->
  <path d="M 120 100 C 132 80, 150 65, 170 63 C 202 60, 222 84, 216 112 C 210 138, 186 150, 162 142 C 140 134, 124 114, 120 100"
        stroke="url(#lg)" stroke-width="22" stroke-linecap="round" fill="none"/>

  <!-- A peak (spike riding the junction) -->
  <path d="M 82 108 L 120 32 L 158 108"
        stroke="url(#lg)" stroke-width="20" stroke-linecap="round" stroke-linejoin="round" fill="none"/>

  <!-- A crossbar -->
  <path d="M 99 90 L 141 90"
        stroke="url(#lg)" stroke-width="14" stroke-linecap="round" fill="none"/>
</svg>
''';
}

/// Gradient wordmark "AniSphere"
class _Wordmark extends StatelessWidget {
  final double width;
  const _Wordmark({required this.width});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => AniSphereBrand.logoGradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        'AniSphere',
        style: TextStyle(
          fontSize: width / 5.2,
          fontWeight: FontWeight.w800,
          color: Colors.white, // masked by ShaderMask
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

/// Gradient border container (for story rings, active elements).
class GradientBorder extends StatelessWidget {
  final Widget child;
  final double borderWidth;
  final double borderRadius;

  const GradientBorder({
    super.key,
    required this.child,
    this.borderWidth = 2.5,
    this.borderRadius = 999,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AniSphereBrand.logoGradient,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      padding: EdgeInsets.all(borderWidth),
      child: child,
    );
  }
}
