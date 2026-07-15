import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/feed_service.dart';

/// Relationship-derived post tally: a count() aggregation over the SAME
/// query shape as the profile Posts tab (posts where userId == uid, no other
/// filters — same index requirements), but UNLIMITED where the tab caps at
/// 50. The header shows the true total; header == tab is guaranteed only at
/// <= 50 posts. Display never reads the denormalized users/{uid}.postsCount
/// field — it is historically under-counted (cause unproven; predates
/// version control) and stays write-only bookkeeping.
final postCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, uid) async {
  final epoch = FeedService.instance.postsEpoch;
  void onPostsChange() => ref.invalidateSelf();
  epoch.addListener(onPostsChange);
  ref.onDispose(() => epoch.removeListener(onPostsChange));

  final agg = await FirebaseFirestore.instance
      .collection('posts')
      .where('userId', isEqualTo: uid)
      .count()
      .get();
  return agg.count ?? 0;
});
