import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../providers/currency_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/language_provider.dart';
import '../providers/user_provider.dart';
import 'ani_gem_icon.dart';
import 'ani_gold_icon.dart';
import 'gradient_button.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Identity (name / handle / verified / avatar) comes from the live
    // users/{uid} doc; the sample userProvider only supplies demo-side
    // extras like the level aura.
    final user = ref.watch(userProvider);
    final me = myIdentity(ref);
    final c = ref.watch(currencyProvider);

    void go(String route, {bool push = true}) {
      Haptics.light();
      Navigator.pop(context);
      push ? context.push(route) : context.go(route);
    }

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            // header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(gradient: AppGradients.pageBg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    name: me?.nameToShow ?? '',
                    imageUrl: me?.userAvatar,
                    level: user.level,
                    radius: 28,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(me?.nameToShow ?? '…', style: AppTextStyles.subheading),
                      const SizedBox(width: 5),
                      if (me?.isVerified == true) const VerifiedBadge(size: BadgeSize.sm),
                    ],
                  ),
                  Text(me == null ? '' : '@${me.userName}', style: AppTextStyles.captionMuted),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const AniGoldIcon(size: BadgeSize.sm),
                      const SizedBox(width: 4),
                      Text(Fmt.thousands(c.gold), style: AppTextStyles.numbers),
                      const SizedBox(width: 14),
                      const AniGemIcon(size: BadgeSize.sm),
                      const SizedBox(width: 4),
                      Text(Fmt.thousands(c.gem), style: AppTextStyles.numbers),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _tile(LucideIcons.home, ref.tr('feed'), () => go('/feed', push: false)),
                  _tile(LucideIcons.compass, ref.tr('discover'), () => go('/discover', push: false)),
                  _tile(LucideIcons.playCircle, ref.tr('aniVideos'), () => go('/ani-videos', push: false)),
                  // Former bottom-nav tabs — pushed full-screen, screens unchanged.
                  _tile(LucideIcons.trendingUp, ref.tr('trending'), () => go('/trending')),
                  _tile(LucideIcons.list, ref.tr('myList'), () => go('/my-list')),
                  _tile(LucideIcons.users, ref.tr('rooms'), () => go('/community')),
                  _tile(LucideIcons.gamepad2, ref.tr('challenges'), () => go('/challenges')),
                  _tile(LucideIcons.calendar, ref.tr('seasonal'), () => go('/seasonal')),
                  _tile(LucideIcons.award, ref.tr('achievements'), () => go('/achievements')),
                  _tile(LucideIcons.wallet, ref.tr('wallet'), () => go('/wallet')),
                  _tile(LucideIcons.globe, ref.tr('observatory'), () => go('/observatory')),
                  _tile(LucideIcons.radio, ref.tr('fmRadio'), () => go('/fm-radio')),
                  _tile(LucideIcons.layers, ref.tr('cardCollection'), () => go('/cards')),
                  _tile(LucideIcons.scanLine, 'AniScan', () => go('/aniscan')),
                  _tile(LucideIcons.settings, ref.tr('settings'), () => go('/settings')),
                ],
              ),
            ),
            if (!user.isPlusUser)
              Padding(
                padding: const EdgeInsets.all(14),
                child: GradientButton(
                  label: 'Upgrade to AniPlus 💎',
                  icon: LucideIcons.sparkles,
                  onPressed: () => go('/wallet?tab=plus'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppGradients.brand,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('💎 AniPlus active',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.textSecondary),
      title: Text(label, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
