import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/follow_service.dart';
import '../../shared/providers/language_provider.dart';
import 'followers_screen.dart';

/// Who [userId] follows. Same list shell as followers; each row's toggle
/// unfollows in place when it's the signed-in user's own list.
class FollowingScreen extends ConsumerWidget {
  final String userId;
  const FollowingScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return UserListScaffold(
      title: ref.tr('following'),
      emptyText: ref.tr('notFollowingAnyone'),
      streamOf: (limit) => FollowService.instance.getUserFollowing(userId, limit: limit),
    );
  }
}
