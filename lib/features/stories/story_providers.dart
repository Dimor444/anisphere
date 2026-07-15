import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/story_service.dart';

/// One user's active stories, oldest → newest (viewer plays them in order).
class StoryGroup {
  final String uid;
  final List<StoryData> stories;
  const StoryGroup({required this.uid, required this.stories});

  StoryData get latest => stories.last;
}

/// Active stories grouped per user, groups ordered by most recent story.
/// Backed by one Firestore listener; expiry is filtered client-side inside
/// [StoryService.getActiveStories].
final activeStoryGroupsProvider = StreamProvider<List<StoryGroup>>((ref) {
  return StoryService.instance.getActiveStories().map((stories) {
    final byUid = <String, List<StoryData>>{};
    for (final s in stories) {
      if (s.uid.isEmpty || s.mediaUrl.isEmpty) continue;
      byUid.putIfAbsent(s.uid, () => []).add(s);
    }
    // One consistent clock per emission: a pending write's createdAt is null
    // until the server resolves the sentinel, and `?? now` sorts it as the
    // newest story. A per-comparison DateTime.now() would give each compare
    // a different fallback and make ordering non-deterministic.
    final now = DateTime.now();
    final groups = byUid.entries.map((e) {
      final list = e.value..sort((a, b) => (a.createdAt ?? now).compareTo(b.createdAt ?? now));
      return StoryGroup(uid: e.key, stories: list);
    }).toList()
      ..sort((a, b) => (b.latest.createdAt ?? now).compareTo(a.latest.createdAt ?? now));
    return groups;
  });
});

/// Story ids the signed-in user viewed THIS session — an overlay so the ring
/// flips to "viewed" instantly, without waiting for a Firestore round-trip.
final viewedOverlayProvider = StateProvider<Set<String>>((_) => <String>{});

/// Whether the signed-in user has viewed [storyId] (overlay first, then the
/// `viewers/{uid}` doc). Used by the ring for the latest story per group.
final storyViewedProvider = FutureProvider.autoDispose.family<bool, String>((ref, storyId) async {
  if (ref.watch(viewedOverlayProvider).contains(storyId)) return true;
  return StoryService.instance.hasViewed(storyId);
});

/// The signed-in uid (guest session included) — for owner checks in the
/// viewer and skipping self-views.
final myUidProvider = FutureProvider<String>((ref) async => (await AuthService.instance.initAuth()).uid);

/// Marks [storyId] viewed: overlay immediately (ring flips), Firestore
/// write behind it (create-only; failures don't block playback).
void markStoryViewed(WidgetRef ref, String storyId) {
  final overlay = ref.read(viewedOverlayProvider.notifier);
  if (overlay.state.contains(storyId)) return;
  overlay.state = {...overlay.state, storyId};
  // ignore: discarded_futures — fire-and-forget; the overlay already covers UI.
  StoryService.instance.markViewed(storyId).ignore();
}
