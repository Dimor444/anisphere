import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../shared/widgets/gradient_button.dart';

/// End-of-game summary for every Games-tab mini-game: final score, AniGold
/// earned this run, and Play Again / Back actions.
class ResultsScreen extends StatelessWidget {
  final String gameTitle;
  final int score;
  final int total;
  final int goldEarned;
  final VoidCallback onPlayAgain;
  final VoidCallback onBack;

  const ResultsScreen({
    super.key,
    required this.gameTitle,
    required this.score,
    required this.total,
    required this.goldEarned,
    required this.onPlayAgain,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final perfect = score == total;
    final decent = score * 2 >= total;
    return Scaffold(
      appBar: AppBar(title: Text(gameTitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(perfect ? '🏆' : (decent ? '🎉' : '💪'), style: const TextStyle(fontSize: 64), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                perfect ? 'Perfect!' : (decent ? 'Nice run!' : 'Keep training!'),
                style: AppTextStyles.heading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'You scored $score / $total',
                style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.aniGold.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.aniGold.withOpacity(0.5)),
                  ),
                  child: Text('+$goldEarned 🟡 AniGold earned', style: AppTextStyles.numbers.copyWith(color: AppColors.aniGold)),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onPlayAgain,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Play Again', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: GradientButton(label: 'Back', onPressed: onBack)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
