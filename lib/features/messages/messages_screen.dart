import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final convos = SampleData.conversations;
    return Scaffold(
      appBar: AppBar(title: const Text('Messages'), actions: [IconButton(icon: const Icon(LucideIcons.pencil, size: 20), onPressed: () {})]),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: convos.length,
        separatorBuilder: (_, __) => const Divider(indent: 78, height: 1),
        itemBuilder: (_, i) {
          final c = convos[i];
          return InkWell(
            onTap: () {
              Haptics.light();
              context.push('/chat/${c.id}');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  UserAvatar.fromUser(c.user, radius: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(c.user.username, style: AppTextStyles.subheading),
                          if (c.user.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: BadgeSize.sm)],
                          const SizedBox(width: 6),
                          if (c.streak > 0) _streakChip(c.streak),
                        ]),
                        const SizedBox(height: 2),
                        Text(c.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMuted.copyWith(fontWeight: c.unread > 0 ? FontWeight.w600 : FontWeight.w400, color: c.unread > 0 ? AppColors.textPrimary : AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Fmt.timeAgo(c.lastTime), style: AppTextStyles.captionMuted),
                      const SizedBox(height: 4),
                      if (c.unread > 0)
                        Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle), constraints: const BoxConstraints(minWidth: 20, minHeight: 20), alignment: Alignment.center, child: Text('${c.unread}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _streakChip(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppColors.streak.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
        child: Text('🔥 $n', style: const TextStyle(fontSize: 11, color: AppColors.streak, fontWeight: FontWeight.w700)),
      );
}
