import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/aniplus_paywall.dart';

/// The center "+" FAB action sheet.
void showCreateSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _CreateSheet(),
  );
}

class _CreateSheet extends ConsumerWidget {
  const _CreateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    final liveLocked = user.followers < 1000 && !user.isPlusUser;

    void close() => Navigator.pop(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            _option(context, '📝', 'New Post', 'Share a thought or review', () {
              close();
              context.push('/create-post');
            }),
            _option(context, '🎬', 'Upload Ani Video', 'Reels-style short video', () {
              close();
              context.push('/ani-videos/upload');
            }),
            _option(context, '⭕', 'Add Story', '24-hour story', () {
              close();
              _toast(context, 'Story camera opening…');
            }),
            _option(
              context,
              '🔴',
              'Go Live',
              liveLocked ? 'Unlocks at 1K followers or AniPlus' : 'Start a live stream',
              () {
                if (liveLocked) {
                  close();
                  showAniPlusPaywall(context, 'Go Live');
                } else {
                  close();
                  _toast(context, 'Going live… 🔴');
                }
              },
              locked: liveLocked,
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context, String emoji, String title, String sub, VoidCallback onTap, {bool locked = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: AppTextStyles.subheading),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        const Icon(LucideIcons.lock, size: 13, color: AppColors.aniGold),
                      ],
                    ],
                  ),
                  Text(sub, style: AppTextStyles.captionMuted),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 1)));
}
