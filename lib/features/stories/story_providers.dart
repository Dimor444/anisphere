import 'package:flutter/foundation.dart';
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
///
/// GATED on there being a signed-in identity, and invalidated by
/// SessionLifecycle on both transitions. The rule for `stories` is
/// `allow read: if signedIn()` — not uid-scoped — so the gate is simply
/// whether anyone is signed in.
///
/// Both halves are needed. The gate alone would not help: the listener that
/// already exists keeps running after sign-out, which is precisely the
/// permission-denied this fixes. The invalidate alone would be worse than
/// useless: this provider is keepAlive and still watched by the stories row
/// at that moment, so invalidating rebuilds it immediately — and without the
/// gate the rebuild opens a NEW Firestore listener with no credential.
/// Together, the invalidate cancels the live listener at the identity
/// transition and the gate makes the rebuild inert.
final activeStoryGroupsProvider = StreamProvider<List<StoryGroup>>((ref) {
  final uid = AuthService.instance.uid;
  if (uid == null) {
    debugPrint('[Stories] no identity — not subscribing');
    return Stream.value(const <StoryGroup>[]);
  }
  debugPrint('[Stories] subscribing as $uid');
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
///
/// Deliberately NOT autoDispose, and cleared by SessionLifecycle instead.
/// Surviving is the entire point: the overlay has to outlive any single story
/// widget so a ring stays flipped for the rest of the session. autoDispose
/// would drop the set whenever no story row happened to be watching and the
/// rings would silently un-flip mid-session — a consumer-visible regression.
/// It still carries the PREVIOUS user's viewing history across a sign-out,
/// which is why the teardown clears it.
final viewedOverlayProvider = StateProvider<Set<String>>((_) => <String>{});

/// Whether the signed-in user has viewed [storyId] (overlay first, then the
/// `viewers/{uid}` doc). Used by the ring for the latest story per group.
final storyViewedProvider = FutureProvider.autoDispose.family<bool, String>((ref, storyId) async {
  if (ref.watch(viewedOverlayProvider).contains(storyId)) return true;
  return StoryService.instance.hasViewed(storyId);
});

/// The signed-in uid (guest session included) — for owner checks in the
/// viewer and skipping self-views. Null when nobody is signed in, which the
/// viewer already treats as "not the owner" and "do not record a view".
///
/// autoDispose is load-bearing here, and was missing: as a plain
/// FutureProvider this cached the resolved uid for the WHOLE app session, so
/// after a sign-out it kept handing out the dead uid to every later reader —
/// a bug in its own right, independent of the exception below. Disposing when
/// unwatched makes each open re-resolve; initAuth is memoized inside
/// AuthService, so re-resolving costs nothing.
final myUidProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    return (await AuthService.instance.initAuth()).uid;
  } on SignedOutException {
    return null;
  }
});

/// Marks [storyId] viewed: overlay immediately (ring flips), Firestore
/// write behind it (create-only; failures don't block playback).
void markStoryViewed(WidgetRef ref, String storyId) {
  final overlay = ref.read(viewedOverlayProvider.notifier);
  if (overlay.state.contains(storyId)) return;
  overlay.state = {...overlay.state, storyId};
  // ignore: discarded_futures — fire-and-forget; the overlay already covers UI.
  StoryService.instance.markViewed(storyId).ignore();
}
