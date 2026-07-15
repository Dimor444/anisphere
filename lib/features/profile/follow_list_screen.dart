import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/user_model.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'profile_screen.dart';

/// A list of users (Followers or Following). Tapping a row opens that user's
/// profile; the Follow button toggles a local follow state.
class FollowListScreen extends StatefulWidget {
  final String title;
  final List<UserModel> users;
  const FollowListScreen({super.key, required this.title, required this.users});

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late final Set<String> _following = {
    for (final u in widget.users)
      if (u.isFollowedByMe) u.id,
  };

  void _toggle(UserModel u) {
    Haptics.light();
    setState(() => _following.contains(u.id) ? _following.remove(u.id) : _following.add(u.id));
  }

  void _openProfile(UserModel u) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(viewUser: u)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · ${widget.users.length}')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: widget.users.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) {
          final u = widget.users[i];
          final following = _following.contains(u.id);
          return ListTile(
            onTap: () => _openProfile(u),
            leading: UserAvatar.fromUser(u, radius: 22),
            title: Row(children: [
              Flexible(child: Text(u.displayName ?? u.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.subheading)),
              if (u.isVerified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge(size: BadgeSize.sm)),
            ]),
            subtitle: Text(u.bio.isNotEmpty ? u.bio : '@${u.username.toLowerCase()}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.captionMuted),
            trailing: GestureDetector(
              onTap: () => _toggle(u),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: following ? null : AppGradients.brand,
                  color: following ? AppColors.surfaceAlt : null,
                  borderRadius: BorderRadius.circular(20),
                  border: following ? Border.all(color: AppColors.border) : null,
                ),
                child: Text(following ? 'Following' : 'Follow', style: TextStyle(color: following ? AppColors.textSecondary : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          );
        },
      ),
    );
  }
}
