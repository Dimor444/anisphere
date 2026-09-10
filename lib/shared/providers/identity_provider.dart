import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';

/// Render-time identity resolution: the live `users/{uid}` doc is the single
/// source of truth for displayName / avatar / isVerified. The copies
/// denormalized onto posts, comments and score docs are write-time snapshots
/// kept only as a loading fallback — always render through these providers so
/// a profile rename propagates everywhere immediately, old docs included.

/// Last emission per uid, kept for the app session so a revisited screen
/// paints the correct identity instantly while its listener re-attaches.
final _lastKnown = <String, UserData>{};

/// Drop every cached identity. Called by the session lifecycle when the
/// signed-in user changes.
///
/// Without this the map outlives the session that filled it, and since
/// [identityOf] falls back to it whenever the live doc has not arrived, the
/// PREVIOUS user's display name and avatar paint over the new session's
/// screens until each listener delivers its first snapshot.
void clearIdentityCache() => _lastKnown.clear();

/// Live identity of any user. The family dedupes: every widget watching the
/// same uid shares one Firestore listener, dropped when the last one leaves.
final identityProvider =
    StreamProvider.autoDispose.family<UserData?, String>((ref, uid) {
  return FollowService.instance.watchUser(uid).map((u) {
    if (u != null) _lastKnown[uid] = u;
    return u;
  });
});

/// Live identity of the signed-in user. The uid comes from the same
/// [AuthService.initAuth] that every profile write resolves (Edit Profile →
/// FollowService.updateProfile), so this can never watch a different doc
/// than the one edits land in.
final myIdentityProvider = StreamProvider.autoDispose<UserData?>((ref) async* {
  final String uid;
  try {
    uid = (await AuthService.instance.initAuth()).uid;
  } on SignedOutException {
    // Signed out is a normal state, not a failure. Yielding null lands in the
    // SAME branch every consumer already handles — myIdentity(ref) returns
    // null while loading too — so no UI has to grow an error case.
    yield null;
    return;
  }
  yield* FollowService.instance.watchUser(uid).map((u) {
    if (u != null) _lastKnown[uid] = u;
    return u;
  });
});

/// Resolved identity for [uid]: live doc when loaded, else the session's
/// last-known value, else null — callers fall back to the field denormalized
/// on the post/comment/score doc.
UserData? identityOf(WidgetRef ref, String uid) {
  if (uid.isEmpty) return null;
  return ref.watch(identityProvider(uid)).asData?.value ?? _lastKnown[uid];
}

/// Resolved identity of the signed-in user, null while loading.
UserData? myIdentity(WidgetRef ref) =>
    ref.watch(myIdentityProvider).asData?.value;
