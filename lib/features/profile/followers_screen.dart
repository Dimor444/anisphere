import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/models/user.dart';
import '../../services/follow_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_tile.dart';

/// Who follows [userId]. Live list, 50 per page with a load-more tail.
class FollowersScreen extends ConsumerWidget {
  final String userId;
  const FollowersScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return UserListScaffold(
      title: ref.tr('followers'),
      emptyText: ref.tr('noFollowersYet'),
      streamOf: (limit) => FollowService.instance.getUserFollowers(userId, limit: limit),
    );
  }
}

/// Shared scaffold for followers/following: paginated live user list with
/// empty and error states.
class UserListScaffold extends ConsumerStatefulWidget {
  final String title;
  final String emptyText;
  final Stream<List<UserData>> Function(int limit) streamOf;
  const UserListScaffold({super.key, required this.title, required this.emptyText, required this.streamOf});

  @override
  ConsumerState<UserListScaffold> createState() => _UserListScaffoldState();
}

class _UserListScaffoldState extends ConsumerState<UserListScaffold> {
  int _limit = FollowService.pageSize;
  late Stream<List<UserData>> _stream = widget.streamOf(_limit);

  void _loadMore() {
    setState(() {
      _limit += FollowService.pageSize;
      _stream = widget.streamOf(_limit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: StreamBuilder<List<UserData>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text(ref.tr('actionFailed'), style: AppTextStyles.captionMuted));
            }
            final users = snap.data;
            if (users == null) return const Center(child: CircularProgressIndicator());
            if (users.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.usersRound, size: 42, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(widget.emptyText, style: AppTextStyles.captionMuted),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: users.length + (users.length >= _limit ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == users.length) {
                  return TextButton(
                    onPressed: _loadMore,
                    child: const Icon(LucideIcons.chevronDown, color: AppColors.primaryLight),
                  );
                }
                return UserTile(key: ValueKey(users[i].id), user: users[i]);
              },
            );
          },
        ),
      ),
    );
  }
}
