import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'verified_badge.dart' show BadgeSize;

/// AniGem currency mark: the green ANISPHERE triangular medallion
/// (asset: assets/icons/anigem.png), with a soft green glow.
class AniGemIcon extends StatelessWidget {
  final BadgeSize size;
  const AniGemIcon({super.key, this.size = BadgeSize.md});

  double get _px => switch (size) {
        BadgeSize.sm => 14,
        BadgeSize.md => 22,
        BadgeSize.lg => 30,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _px,
      height: _px,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.aniGem.withOpacity(0.55),
            blurRadius: _px * 0.45,
          ),
        ],
      ),
      child: Image.asset('assets/icons/anigem.png', width: _px, height: _px, fit: BoxFit.contain),
    );
  }
}
