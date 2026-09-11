import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../services/streak_service.dart';
import '../providers/currency_provider.dart';
import '../providers/identity_provider.dart';
import 'ani_gold_icon.dart';
import 'ani_gem_icon.dart';
import 'verified_badge.dart' show BadgeSize;

/// The Feed/Wallet currency strip: AniGold | AniGem | 🔥 streak.
class CurrencyBar extends ConsumerWidget {
  final EdgeInsetsGeometry padding;
  const CurrencyBar({super.key, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8)});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(currencyProvider);

    // The streak is the real one: users/{uid}.currentStreak, resolved through
    // the same identity family the profile uses (identityOf there, its
    // own-user twin myIdentity here) and passed through the same
    // [StreakService.displayStreak] — so the feed and the profile can never
    // disagree about a user's streak.
    //
    // Gold and gem still come from currencyProvider. They are a separate
    // question: no server field exists for either, so there is nothing yet to
    // read them from.
    //
    // null covers loading, signed-out and a missing doc alike — myIdentity
    // returns null for all three. It renders an em dash rather than a number,
    // because the alternative is flashing a confident value for an account
    // whose streak has not been read yet.
    final me = myIdentity(ref);
    final streak = me == null
        ? null
        : StreakService.displayStreak(
            currentStreak: me.currentStreak,
            lastActiveDay: me.lastActiveDay,
          );

    return Padding(
      padding: padding,
      child: Row(
        children: [
          _Pill(icon: const AniGoldIcon(size: BadgeSize.sm), value: Fmt.thousands(c.gold)),
          const SizedBox(width: 10),
          _Pill(icon: const AniGemIcon(size: BadgeSize.sm), value: Fmt.thousands(c.gem)),
          const SizedBox(width: 10),
          _Pill(
            icon: const Text('🔥', style: TextStyle(fontSize: 14)),
            // "1 days" was reachable the moment this read a real value — a
            // one-day streak is the common case on a new account.
            value: streak == null
                ? '—'
                : '$streak ${streak == 1 ? 'day' : 'days'}',
            tint: AppColors.streak,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Widget icon;
  final String value;
  final Color? tint;
  const _Pill({required this.icon, required this.value, this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (tint ?? AppColors.border).withOpacity(tint != null ? 0.5 : 1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Text(value, style: AppTextStyles.numbers),
        ],
      ),
    );
  }
}

/// Inline gold price tag, e.g. "444 🟡".
class GoldTag extends StatelessWidget {
  final int amount;
  final BadgeSize size;
  const GoldTag(this.amount, {super.key, this.size = BadgeSize.sm});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AniGoldIcon(size: size),
        const SizedBox(width: 4),
        Text(Fmt.thousands(amount),
            style: AppTextStyles.numbers.copyWith(color: AppColors.aniGold)),
      ],
    );
  }
}

class GemTag extends StatelessWidget {
  final int amount;
  final BadgeSize size;
  const GemTag(this.amount, {super.key, this.size = BadgeSize.sm});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AniGemIcon(size: size),
        const SizedBox(width: 4),
        Text(Fmt.thousands(amount),
            style: AppTextStyles.numbers.copyWith(color: AppColors.aniGem)),
      ],
    );
  }
}
