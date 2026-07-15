import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/user_avatar.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'All'), Tab(text: 'Follows'), Tab(text: 'Activity'), Tab(text: 'Streaks'), Tab(text: 'Tasks')],
          ),
        ),
        body: TabBarView(children: [
          _list(SampleData.notifications),
          _list(SampleData.notifications.where((n) => n.type == NotifType.follow || n.type == NotifType.friend).toList()),
          _list(SampleData.notifications.where((n) => n.type == NotifType.like || n.type == NotifType.newEpisode || n.type == NotifType.smart || n.type == NotifType.trueFan).toList()),
          _list(SampleData.notifications.where((n) => n.type == NotifType.streakWarning || n.type == NotifType.streakBonus).toList()),
          _list(SampleData.notifications.where((n) => n.type == NotifType.streakBonus).toList()),
        ]),
      ),
    );
  }

  Widget _list(List<NotificationItem> items) {
    if (items.isEmpty) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text('🔔', style: TextStyle(fontSize: 48)), SizedBox(height: 8), Text('Nothing here yet', style: AppTextStyles.bodyMuted)]));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (_, i) => _NotifTile(item: items[i]),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final NotificationItem item;
  const _NotifTile({required this.item});

  (IconData, Color) get _meta => switch (item.type) {
        NotifType.follow => (LucideIcons.userPlus, AppColors.primary),
        NotifType.like => (LucideIcons.heart, AppColors.secondary),
        NotifType.newEpisode => (LucideIcons.tv, AppColors.accent),
        NotifType.streakWarning => (LucideIcons.flame, AppColors.error),
        NotifType.streakBonus => (LucideIcons.flame, AppColors.aniGold),
        NotifType.friend => (LucideIcons.users, AppColors.aniGem),
        NotifType.trueFan => (LucideIcons.trophy, AppColors.aniGold),
        NotifType.smart => (LucideIcons.sparkles, AppColors.primaryLight),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _meta;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (item.user != null)
            UserAvatar.fromUser(item.user!, radius: 22)
          else
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(style: AppTextStyles.body, children: [
                    if (item.user != null) TextSpan(text: '${item.user!.username} ', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    TextSpan(text: item.text, style: const TextStyle(color: AppColors.textSecondary)),
                  ]),
                ),
                Text(Fmt.timeAgo(item.time), style: AppTextStyles.captionMuted),
              ],
            ),
          ),
          if (item.type == NotifType.follow)
            GestureDetector(
              onTap: () => Haptics.light(),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)), child: const Text('Follow Back', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
            ),
        ],
      ),
    );
  }
}
