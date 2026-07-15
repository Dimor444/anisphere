import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../data/models/user_profile.dart';
import 'auth_service.dart';

/// Read side of the signed-in user's Profile header.
///
/// Reuses the exact paths the write-side services own:
///  - profile doc   `users/{uid}`                        (FollowService.ensureProfile)
///  - anime list    `users/{uid}/myList`                 (MyListService)
///  - follow graph  `users/{uid}/followers` + `users/{uid}/following` (FollowService)
///
/// Counts are count() aggregations — no documents are downloaded.
class ProfileRepository {
  ProfileRepository._();
  static final ProfileRepository instance = ProfileRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Live `users/{uid}` — null until the profile doc exists.
  Stream<UserProfile?> watchProfile() async* {
    final uid = await _uid();
    debugPrint('[ProfileRepository] watching users/$uid');
    yield* _userDoc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserProfile.fromFirestore(doc) : null);
  }

  Future<int> _count(String uid, String sub) async {
    final agg = await _userDoc(uid).collection(sub).count().get();
    return agg.count ?? 0;
  }

  /// myList size only — follow tallies come from followCountsProvider, which
  /// re-counts on every follow/unfollow instead of once per session.
  Future<int> fetchMyListCount() async => _count(await _uid(), 'myList');

  /// Anime / followers / following tallies — three parallel aggregations.
  Future<ProfileCounts> fetchCounts() async {
    final uid = await _uid();
    final counts = await Future.wait([
      _count(uid, 'myList'),
      _count(uid, 'followers'),
      _count(uid, 'following'),
    ]);
    debugPrint('[ProfileRepository] counts for users/$uid — '
        'myList: ${counts[0]}, followers: ${counts[1]}, following: ${counts[2]}');
    return ProfileCounts(anime: counts[0], followers: counts[1], following: counts[2]);
  }

  /// "March 2024" — the profile's createdAt, falling back to the auth
  /// account's creation time when the doc is missing or predates the field.
  String joinDate(UserProfile? profile) {
    final t = profile?.createdAt ??
        FirebaseAuth.instance.currentUser?.metadata.creationTime;
    return t == null ? '—' : DateFormat('MMMM yyyy').format(t.toLocal());
  }
}

class ProfileCounts {
  final int anime;
  final int followers;
  final int following;
  const ProfileCounts({required this.anime, required this.followers, required this.following});
}
