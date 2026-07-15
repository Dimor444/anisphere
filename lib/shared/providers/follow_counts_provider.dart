import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/follow_service.dart';

/// Relationship-derived follow tallies: count() aggregations over
/// users/{uid}/followers and users/{uid}/following. All display surfaces read
/// these — never the denormalized followerCount/followingCount doc fields,
/// which remain write-only bookkeeping until a server-side owner exists.
class FollowCounts {
  final int followers;
  final int following;
  const FollowCounts({required this.followers, required this.following});
}

/// Live counts for any user. Re-runs whenever the signed-in user follows or
/// unfollows anyone ([FollowService.followGraphEpoch]); a recount is two
/// index-only aggregation reads, no documents are downloaded.
final followCountsProvider =
    FutureProvider.autoDispose.family<FollowCounts, String>((ref, uid) async {
  final epoch = FollowService.instance.followGraphEpoch;
  void onGraphChange() => ref.invalidateSelf();
  epoch.addListener(onGraphChange);
  ref.onDispose(() => epoch.removeListener(onGraphChange));

  final user = FirebaseFirestore.instance.collection('users').doc(uid);
  final counts = await Future.wait([
    user.collection('followers').count().get(),
    user.collection('following').count().get(),
  ]);
  return FollowCounts(
    followers: counts[0].count ?? 0,
    following: counts[1].count ?? 0,
  );
});

/// [followCountsProvider] for the signed-in user — uid resolved through the
/// same [AuthService.initAuth] every FollowService write resolves.
final myFollowCountsProvider =
    FutureProvider.autoDispose<FollowCounts>((ref) async {
  final uid = (await AuthService.instance.initAuth()).uid;
  return ref.watch(followCountsProvider(uid).future);
});
