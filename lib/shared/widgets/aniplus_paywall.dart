import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import 'gradient_button.dart';

/// Shows the AniPlus paywall for a locked AI/premium feature.
Future<void> showAniPlusPaywall(BuildContext context, String feature) {
  Haptics.medium();
  return showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('💎', style: TextStyle(fontSize: 30)),
            ),
            const SizedBox(height: 14),
            Text(feature, style: AppTextStyles.heading, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('AniPlus Exclusive 💎',
                style: AppTextStyles.bodyMuted.copyWith(color: AppColors.primaryLight)),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(children: [
                TextSpan(text: '\$4.44', style: AppTextStyles.numbersXl(color: Colors.white)),
                const TextSpan(text: '/month', style: AppTextStyles.bodyMuted),
              ]),
            ),
            const SizedBox(height: 18),
            GradientButton(
              label: 'Subscribe Now',
              icon: Icons.bolt_rounded,
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/wallet?tab=plus');
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Maybe later', style: AppTextStyles.caption.copyWith(color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Wraps a premium feature. When [locked], overlays a 💎 scrim and routes taps
/// to the paywall instead of the child's action.
class PlusLock extends StatelessWidget {
  final bool locked;
  final String feature;
  final Widget child;
  final double radius;
  const PlusLock({
    super.key,
    required this.locked,
    required this.feature,
    required this.child,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Material(
              color: Colors.black.withOpacity(0.45),
              child: InkWell(
                onTap: () => showAniPlusPaywall(context, feature),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_rounded, color: Colors.white, size: 20),
                      SizedBox(height: 4),
                      Text('💎 AniPlus', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small inline 💎 chip to mark Plus-only entry points.
class PlusChip extends StatelessWidget {
  const PlusChip({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('💎 Plus', style: TextStyle(color: AppGradients.onFill(AppGradients.brand.colors.first), fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }
}
