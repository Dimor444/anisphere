import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/user_model.dart';

/// Small gradient pill showing a user's level, e.g. "Otaku Elite 👑".
class LevelBadge extends StatelessWidget {
  final UserLevel level;
  final bool compact;
  const LevelBadge({super.key, required this.level, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: level.gradient),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: level.gradient.last.withOpacity(0.4), blurRadius: 8),
        ],
      ),
      child: Text(
        compact ? level.emoji : level.title,
        style: TextStyle(
          fontSize: compact ? 11 : 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.onBrand,
        ),
      ),
    );
  }
}
