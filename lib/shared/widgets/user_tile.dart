import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/user.dart';
import 'follow_button.dart';
import 'user_avatar.dart';
import '../../services/currency_service.dart';
import 'user_name_text.dart';

/// One user row (followers/following lists, suggestions, search results):
/// small avatar, name + badge, bio snippet, follow toggle. Tapping the row
/// opens the profile.
class UserTile extends StatelessWidget {
  final UserData user;

  /// Extra line under the bio (e.g. follower count on suggestion cards).
  final String? subtitle;
  const UserTile({super.key, required this.user, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Haptics.light();
        context.push('/profile/${user.id}');
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            UserAvatar(name: user.nameToShow, imageUrl: user.userAvatar, radius: 20, frame: user.equippedIn(CosmeticSlot.frame)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserNameText(user: user, style: AppTextStyles.subheading),
                  // Handle first (like the profile header), bio tucked after.
                  UserHandleText(
                    user: user,
                    style: AppTextStyles.captionMuted,
                    suffix: user.bio.isNotEmpty ? ' · ${user.bio}' : '',
                  ),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: AppTextStyles.captionMuted.copyWith(color: AppColors.primaryLight)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            FollowButton(userId: user.id, compact: true),
          ],
        ),
      ),
    );
  }
}
