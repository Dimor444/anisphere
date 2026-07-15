import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'story_providers.dart';
import 'story_upload_sheet.dart';

/// Avatar row above the feed: "Add Story" plus everyone with an active
/// (unexpired) story. Gradient ring = their latest story is unviewed;
/// muted ring = seen. Identity renders through [identityProvider].
class StoriesRow extends ConsumerWidget {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(activeStoryGroupsProvider).asData?.value ?? const <StoryGroup>[];
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (i == 0) return const _AddStoryButton();
          return _StoryRing(group: groups[i - 1]);
        },
      ),
    );
  }
}

class _AddStoryButton extends ConsumerWidget {
  const _AddStoryButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => startStoryUpload(context, ref),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceAlt,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(LucideIcons.plus, color: AppColors.primaryLight),
          ),
          const SizedBox(height: 4),
          Text(ref.tr('addStory'), style: AppTextStyles.captionMuted),
        ],
      ),
    );
  }
}

class _StoryRing extends ConsumerWidget {
  final StoryGroup group;
  const _StoryRing({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = identityOf(ref, group.uid);
    // Unviewed until proven otherwise so a fresh story never flashes grey.
    final viewed = ref.watch(storyViewedProvider(group.latest.id)).asData?.value ?? false;

    return GestureDetector(
      onTap: () {
        Haptics.light();
        context.push('/story', extra: group);
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: viewed ? null : AppGradients.brandTri,
              color: viewed ? AppColors.border : null,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
              child: UserAvatar(
                name: user?.nameToShow ?? '…',
                imageUrl: user?.userAvatar,
                radius: 26,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    user?.nameToShow ?? '…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.captionMuted,
                  ),
                ),
                if (user?.isVerified == true) ...[
                  const SizedBox(width: 2),
                  const VerifiedBadge(size: BadgeSize.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
