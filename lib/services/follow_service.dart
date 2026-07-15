import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/user.dart';
import 'auth_service.dart';

/// Thrown by [FollowService.claimUserName] when another user holds the handle.
class UserNameTakenException implements Exception {
  final String handle;
  const UserNameTakenException(this.handle);
  @override
  String toString() => 'UserNameTakenException(@$handle)';
}

/// The follow graph and public profiles (`users/{userId}` plus symmetric
/// `following`/`followers` subcollections).
///
/// A follow is one batch of four writes: my `following/{target}` doc, the
/// target's `followers/{me}` doc, and a +1 on each side's counter. Security
/// rules pin the subcollection docs to the acting user and only admit ±1
/// counter bumps, so the client can't forge counts. When Cloud Functions
/// land, the counter writes move server-side.
///
/// Follow docs carry only ids + timestamps — profiles are fetched separately
/// (one doc read each) so user data is never duplicated.
class FollowService {
  FollowService._();
  static final FollowService instance = FollowService._();

  static const int pageSize = 50;

  /// whereIn ceiling — feed filtering caps at this many followed authors.
  static const int feedAuthorCap = 30;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[FollowService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[FollowService] $op failed: $e');
      rethrow;
    }
  }

  // ── Profile ────────────────────────────────────────────────────────────

  /// The device locale's country code, uppercased ("SA", "JP", …), or "XX"
  /// when the locale doesn't carry one. Detected once per profile and cached
  /// in the doc — no manual picker yet.
  static String detectCountryCode() {
    final raw = PlatformDispatcher.instance.locale.countryCode?.trim() ?? '';
    if (raw.length < 2 || raw.length > 3) return 'XX';
    return raw.toUpperCase();
  }

  /// Make sure the signed-in user has a public profile doc — create-only.
  ///
  /// Creates `users/{uid}` with neutral defaults (generated handle, zeroed
  /// counters, never verified) when the doc is missing. An existing doc is
  /// left untouched — identity fields are owned by profile edits and must
  /// never be clobbered on startup. isVerified cannot be set from the client
  /// at all: verification is granted server-side only (enforced by rules).
  /// The locale-detected countryCode is written on create and backfilled once
  /// on pre-existing docs that don't have it yet — never re-detected after.
  Future<void> ensureProfile({
    String userName = '',
    String displayName = 'Anime Fan',
    String userAvatar = '',
    String bio = '',
    bool isPlus = false,
  }) {
    return _guard('ensureProfile', () async {
      final uid = await _uid();
      final doc = _users.doc(uid);
      final existing = await doc.get();
      if (existing.exists) {
        if ((existing.data()?['countryCode'] as String? ?? '').isEmpty) {
          await doc.update({'countryCode': detectCountryCode()});
        }
        _logProfile(uid, existing.data());
        return;
      }
      await doc.set(UserData(
        id: uid,
        userName: userName.isNotEmpty ? userName : 'anifan_${uid.substring(0, 6).toLowerCase()}',
        displayName: displayName,
        userAvatar: userAvatar,
        bio: bio,
        isPlus: isPlus,
        countryCode: detectCountryCode(),
      ).toMap());
      _logProfile(uid, (await doc.get()).data());
    });
  }

  void _logProfile(String uid, Map<String, dynamic>? d) => debugPrint(
      '[FollowService] users/$uid — userName: ${d?['userName']}, '
      'displayName: ${d?['displayName']}, bio: "${d?['bio']}", '
      'isVerified: ${d?['isVerified']}, createdAt: ${d?['createdAt']}');

  /// Mirror the session's AniPlus flag onto the profile — community-vote
  /// rules read it (slots 2-4). Touches only isPlus, never identity fields.
  Future<void> updatePlus(bool isPlus) {
    return _guard('updatePlus', () async {
      final uid = await _uid();
      await _users.doc(uid).update({'isPlus': isPlus});
    });
  }

  /// Owner edit from the Edit Profile sheet — writes ONLY displayName + bio.
  /// merge-set so counters, createdAt, isVerified, isPlus are never touched
  /// (rules block them from clients regardless). userNameLower mirrors the
  /// userName handle, not displayName, so it stays as-is.
  Future<void> updateProfile({required String displayName, required String bio}) {
    return _guard('updateProfile', () async {
      final uid = await _uid();
      final doc = _users.doc(uid);
      await doc.set({
        'displayName': displayName.trim(),
        'bio': bio.length > UserData.maxBioLength ? bio.substring(0, UserData.maxBioLength) : bio,
      }, SetOptions(merge: true));
      _logProfile(uid, (await doc.get()).data());
    });
  }

  Future<void> updateBio(String bio) {
    return _guard('updateBio', () async {
      final uid = await _uid();
      await _users.doc(uid).update({
        'bio': bio.length > UserData.maxBioLength ? bio.substring(0, UserData.maxBioLength) : bio,
      });
    });
  }

  // ── Usernames (@handles) ────────────────────────────────────────────────
  // NOTE: the unique @handle IS the existing users/{uid}.userName field —
  // deliberately NOT a new `username` field, so identity stays in one place
  // (models, denormalized copies, userNameLower prefix search all keep
  // working). displayName remains the editable, non-unique nickname.
  // Uniqueness lives in the usernames/{handle} registry ({ uid }): rules
  // only allow creating an absent doc, and users/{uid}.userName may only
  // change in the same transaction that claims the matching registry doc.

  /// Lowercase letters, digits, underscore; 3–20 chars — mirrors the rules.
  static final RegExp handlePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Client mirror of the rules' reserved list, for instant UX feedback —
  /// the rules are the actual enforcement.
  static const Set<String> reservedHandles = {
    'admin', 'administrator', 'anisphere', 'anisphere_official',
    'support', 'mod', 'moderator', 'official', 'help', 'staff',
    'system', 'root', 'api', 'team', 'security', 'verified',
    'anonymous', 'null', 'undefined',
  };

  CollectionReference<Map<String, dynamic>> get _usernames =>
      _db.collection('usernames');

  /// [source] reduced to a legal handle: lowercased, invalid chars dropped.
  /// Falls back to [fallback] (assumed legal) when under 3 chars remain.
  static String suggestHandle(String source, {required String fallback}) {
    final cleaned = source.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final capped = cleaned.length > 20 ? cleaned.substring(0, 20) : cleaned;
    return capped.length >= 3 ? capped : fallback;
  }

  /// True when [handle] is legal and free (or already the caller's own).
  Future<bool> isUserNameAvailable(String handle) {
    return _guard('isUserNameAvailable($handle)', () async {
      final h = handle.trim().toLowerCase();
      if (!handlePattern.hasMatch(h) || reservedHandles.contains(h)) return false;
      final doc = await _usernames.doc(h).get();
      if (!doc.exists) return true;
      return doc.data()?['uid'] == await _uid();
    });
  }

  /// Whether the signed-in user still needs to claim their @handle: true
  /// until usernames/{their handle} exists and is theirs. Throws on network
  /// failure — callers decide whether to skip or retry.
  Future<bool> needsUserNameClaim() {
    return _guard('needsUserNameClaim', () async {
      final uid = await _uid();
      final me = await getUser(uid);
      if (me == null) return false; // no profile doc yet — nothing to gate
      final h = me.userNameLower.isNotEmpty ? me.userNameLower : me.userName.toLowerCase();
      if (h.isEmpty) return true;
      final claim = await _usernames.doc(h).get();
      return !claim.exists || claim.data()?['uid'] != uid;
    });
  }

  /// Atomically claim [handle] for the signed-in user: create
  /// usernames/{handle}, point users/{uid}.userName(+Lower) at it, and
  /// release the previously claimed handle. One transaction, so the rules'
  /// getAfter(usernames/{handle}) check sees the fresh registry doc and the
  /// handle can never change without its claim.
  ///
  /// Throws [UserNameTakenException] when someone else holds it; other
  /// failures (offline, rules) rethrow as-is.
  Future<void> claimUserName(String handle) {
    return _guard('claimUserName($handle)', () async {
      final h = handle.trim().toLowerCase();
      if (!handlePattern.hasMatch(h)) throw ArgumentError('invalid handle: $handle');
      if (reservedHandles.contains(h)) throw UserNameTakenException(h);

      final uid = await _uid();
      await _db.runTransaction((tx) async {
        // All reads before any write (Firestore transaction contract).
        final newClaim = await tx.get(_usernames.doc(h));
        if (newClaim.exists) {
          if (newClaim.data()?['uid'] == uid) return; // already mine — no-op
          throw UserNameTakenException(h);
        }
        final me = await tx.get(_users.doc(uid));
        final old = (me.data()?['userNameLower'] as String? ?? '').trim();
        DocumentSnapshot<Map<String, dynamic>>? oldClaim;
        if (old.isNotEmpty && old != h) {
          oldClaim = await tx.get(_usernames.doc(old));
        }

        tx.set(_usernames.doc(h), {'uid': uid});
        tx.update(_users.doc(uid), {'userName': h, 'userNameLower': h});
        if (oldClaim != null && oldClaim.exists && oldClaim.data()?['uid'] == uid) {
          tx.delete(oldClaim.reference);
        }
      });
      debugPrint('[FollowService] claimed @$h for $uid');
    });
  }

  /// Live profile — null when the user doesn't exist.
  Stream<UserData?> watchUser(String userId) =>
      _users.doc(userId).snapshots().map((doc) => doc.exists ? UserData.fromDoc(doc) : null);

  Future<UserData?> getUser(String userId) {
    return _guard('getUser($userId)', () async {
      final doc = await _users.doc(userId).get();
      return doc.exists ? UserData.fromDoc(doc) : null;
    });
  }

  // ── Follow / unfollow ──────────────────────────────────────────────────

  /// Bumped after every successful follow/unfollow commit. The relationship-
  /// derived count providers re-run their count() aggregations when this
  /// changes — display never reads the denormalized counter fields.
  final ValueNotifier<int> followGraphEpoch = ValueNotifier(0);

  Future<void> followUser(String targetUid) {
    return _guard('follow($targetUid)', () async {
      final uid = await _uid();
      if (uid == targetUid) return;
      // Idempotence gate on the actual doc, not on button state: re-following
      // would otherwise update followers/{me} (rules allow create+delete only
      // — the whole batch is denied) and double-bump the counters.
      final existing = await _users.doc(uid).collection('following').doc(targetUid).get();
      if (existing.exists) return;
      final batch = _db.batch()
        ..set(_users.doc(uid).collection('following').doc(targetUid),
            {'followedAt': FieldValue.serverTimestamp()})
        ..set(_users.doc(targetUid).collection('followers').doc(uid),
            {'followedAt': FieldValue.serverTimestamp()})
        ..update(_users.doc(uid), {'followingCount': FieldValue.increment(1)})
        ..update(_users.doc(targetUid), {'followerCount': FieldValue.increment(1)});
      await batch.commit();
      followGraphEpoch.value++;
    });
  }

  Future<void> unfollowUser(String targetUid) {
    return _guard('unfollow($targetUid)', () async {
      final uid = await _uid();
      if (uid == targetUid) return;
      final existing = await _users.doc(uid).collection('following').doc(targetUid).get();
      if (!existing.exists) return;
      final batch = _db.batch()
        ..delete(_users.doc(uid).collection('following').doc(targetUid))
        ..delete(_users.doc(targetUid).collection('followers').doc(uid))
        ..update(_users.doc(uid), {'followingCount': FieldValue.increment(-1)})
        ..update(_users.doc(targetUid), {'followerCount': FieldValue.increment(-1)});
      await batch.commit();
      followGraphEpoch.value++;
    });
  }

  Future<bool> isFollowing(String targetUid) async {
    try {
      final uid = await _uid();
      final doc = await _users.doc(uid).collection('following').doc(targetUid).get();
      return doc.exists;
    } catch (e) {
      debugPrint('[FollowService] isFollowing($targetUid) failed: $e');
      return false;
    }
  }

  /// Real-time follow state — drives FollowButton.
  Stream<bool> watchIsFollowing(String targetUid) async* {
    final uid = await _uid();
    yield* _users.doc(uid).collection('following').doc(targetUid).snapshots().map((d) => d.exists);
  }

  /// Ids the signed-in user follows (used by the feed filter + suggestions).
  Future<List<String>> followingIds() async {
    try {
      final uid = await _uid();
      final snap = await _users.doc(uid).collection('following').get();
      return snap.docs.map((d) => d.id).toList();
    } catch (e) {
      debugPrint('[FollowService] followingIds failed: $e');
      return const [];
    }
  }

  /// Live view of [followingIds]: null until the first snapshot arrives,
  /// then always current. One Firestore listener behind it; any number of
  /// widgets can listen and re-listen freely (no stream-lifecycle footguns —
  /// this is what the feed's following/popular mode switch hangs off).
  final ValueNotifier<List<String>?> followingIdsListenable = ValueNotifier(null);
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followingSub;
  String? _watchedUid;

  /// Start (or re-point after a sign-in change) the shared following watch.
  /// Idempotent — safe to call from every screen that needs it.
  Future<void> ensureFollowingWatch() async {
    try {
      final uid = await _uid();
      if (_watchedUid == uid) return;
      _watchedUid = uid;
      await _followingSub?.cancel();
      followingIdsListenable.value = null;
      _followingSub = _users.doc(uid).collection('following').snapshots().listen(
        (snap) => followingIdsListenable.value = snap.docs.map((d) => d.id).toList(),
        onError: (Object e) => debugPrint('[FollowService] following watch failed: $e'),
      );
    } catch (e) {
      debugPrint('[FollowService] ensureFollowingWatch failed: $e');
    }
  }

  Future<bool> hasAnyFollowing() async => (await followingIds()).isNotEmpty;

  // ── Lists (profiles resolved per id — no duplicated user data) ─────────

  Stream<List<UserData>> getUserFollowing(String userId, {int limit = pageSize}) =>
      _idsToProfiles(_users.doc(userId).collection('following'), limit);

  Stream<List<UserData>> getUserFollowers(String userId, {int limit = pageSize}) =>
      _idsToProfiles(_users.doc(userId).collection('followers'), limit);

  Stream<List<UserData>> _idsToProfiles(CollectionReference<Map<String, dynamic>> col, int limit) {
    return col.orderBy('followedAt', descending: true).limit(limit).snapshots().asyncMap((snap) async {
      final profiles = await Future.wait(snap.docs.map((d) => getUser(d.id)));
      return profiles.whereType<UserData>().toList();
    });
  }

  // ── Suggestions & search ───────────────────────────────────────────────

  /// Newest users the signed-in user doesn't follow yet (self excluded).
  /// Ordered by profile creation — follower counters are write-only
  /// bookkeeping and are never read for ranking or display.
  Stream<List<UserData>> getFollowSuggestions({int limit = 10}) {
    return _users
        .orderBy('createdAt', descending: true)
        .limit(limit * 3)
        .snapshots()
        .asyncMap((snap) async {
      final uid = await _uid();
      final mine = (await followingIds()).toSet();
      return snap.docs
          .map(UserData.fromDoc)
          .where((u) => u.id != uid && !mine.contains(u.id))
          .take(limit)
          .toList();
    });
  }

  /// Prefix search on userName (via the lowercased copy), most-followed first.
  Future<List<UserData>> searchUsers(String query, {int limit = 20}) {
    return _guard('searchUsers', () async {
      final q = query.trim().toLowerCase();
      if (q.isEmpty) return const <UserData>[];
      final snap = await _users
          .where('userNameLower', isGreaterThanOrEqualTo: q)
          .where('userNameLower', isLessThan: '$q')
          .limit(limit)
          .get();
      final results = snap.docs.map(UserData.fromDoc).toList()
        ..sort((a, b) => b.followerCount.compareTo(a.followerCount));
      return results;
    });
  }
}
