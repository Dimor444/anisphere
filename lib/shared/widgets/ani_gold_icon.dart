import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'verified_badge.dart' show BadgeSize;

/// AniGold currency mark: a radial-gold coin with an infinity glyph.
class AniGoldIcon extends StatelessWidget {
  final BadgeSize size;
  const AniGoldIcon({super.key, this.size = BadgeSize.md});

  double get _px => switch (size) {
        BadgeSize.sm => 16,
        BadgeSize.md => 24,
        BadgeSize.lg => 32,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _px,
      height: _px,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [AppColors.aniGoldBright, AppColors.aniGoldDeep],
          radius: 0.95,
        ),
        border: Border.all(color: const Color(0xFFDAA520), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.aniGold.withOpacity(0.45),
            blurRadius: _px * 0.4,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '∞',
        style: TextStyle(
          fontSize: _px * 0.62,
          height: 1,
          fontWeight: FontWeight.w900,
          color: const Color(0xFF6B4A06),
        ),
      ),
    );
  }
}
