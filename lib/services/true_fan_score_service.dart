import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'follow_service.dart';

/// One row of a True Fan leaderboard.
class TrueFanScoreEntry {
  final String userId;
  final String userName;
  final String userAvatar;
  final String countryCode;
  final int score;
  final double timeSeconds;

  const TrueFanScoreEntry({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.countryCode,
    required this.score,
    required this.timeSeconds,
  });

  factory TrueFanScoreEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return TrueFanScoreEntry(
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? 'Anonymous',
      userAvatar: d['userAvatar'] as String? ?? '',
      countryCode: d['countryCode'] as String? ?? '',
      score: (d['score'] as num?)?.toInt() ?? 0,
      timeSeconds: (d['timeSeconds'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Per-anime True Fan leaderboards, stored in `trueFanScores/{uid}_{anilistId}`
/// — one doc per user per anime, so a PASS is a natural upsert.
///
/// Only passing runs (score >= [passScore]) are written, always with
/// `passed: true`, and only when they beat the user's stored best time.
/// The user's profile identity (userName/userAvatar) and countryCode are
/// denormalized onto the doc at write time — Firestore can't join, and the
/// Local (country) leaderboard filters on the score doc itself.
///
/// Rankings are by [timeSeconds] ascending among passed runs. Exact ranks
/// outside the visible top of the board come from a count() aggregation
/// (docs with a strictly lower time, plus one).
class TrueFanScoreService {
  TrueFanScoreService._();
  static final TrueFanScoreService instance = TrueFanScoreService._();

  /// Correct answers (out of 10) needed for a run to count as a PASS —
  /// aligned with the result card's "TRUE FAN" tier (7+).
  static const int passScore = 7;

  /// Rows fetched for the visible top of each leaderboard tab.
  static const int leaderboardSize = 44;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _scores => _db.collection('trueFanScores');

  String _docId(String uid, int anilistId) => '${uid}_$anilistId';

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[TrueFanScoreService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[TrueFanScoreService] $op failed: $e');
      rethrow;
    }
  }

  /// Record a passing run for [anilistId]. No-op (returns false) when the run
  /// isn't a pass or when the user already holds an equal-or-better time.
  /// Identity fields come from the user's own profile doc at write time.
  Future<bool> submitPass({
    required int anilistId,
    required String animeTitle,
    required int score,
    required double timeSeconds,
  }) {
    return _guard('submitPass($anilistId)', () async {
      if (score < passScore || timeSeconds <= 0) return false;
      final uid = (await AuthService.instance.initAuth()).uid;
      final doc = _scores.doc(_docId(uid, anilistId));

      final existing = await doc.get();
      final existingTime = (existing.data()?['timeSeconds'] as num?)?.toDouble();
      if (existingTime != null && existingTime <= timeSeconds) {
        debugPrint('[TrueFanScoreService] kept existing best ${existingTime}s '
            '(new run ${timeSeconds}s) for anime $anilistId.');
        return false;
      }

      final profile = await FollowService.instance.getUser(uid);
      await doc.set({
        'userId': uid,
        'anilistId': anilistId,
        'animeTitle': animeTitle,
        'passed': true,
        'score': score,
        'timeSeconds': timeSeconds,
        'userName': profile?.userName ?? 'Anonymous',
        'userAvatar': profile?.userAvatar ?? '',
        // Denormalized so the Local tab can filter without a join.
        'countryCode': profile?.countryCode.isNotEmpty == true
            ? profile!.countryCode
            : FollowService.detectCountryCode(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[TrueFanScoreService] recorded pass for anime $anilistId: '
          '$score/10 in ${timeSeconds}s.');
      return true;
    });
  }

  Query<Map<String, dynamic>> _passedQuery(int anilistId, {String? countryCode}) {
    var q = _scores.where('anilistId', isEqualTo: anilistId).where('passed', isEqualTo: true);
    if (countryCode != null) q = q.where('countryCode', isEqualTo: countryCode);
    return q;
  }

  /// Fastest passing runs for [anilistId], best time first — worldwide, or a
  /// single country when [countryCode] is given. At most [leaderboardSize].
  Future<List<TrueFanScoreEntry>> topScores(int anilistId, {String? countryCode}) {
    return _guard('topScores($anilistId, $countryCode)', () async {
      final snap = await _passedQuery(anilistId, countryCode: countryCode)
          .orderBy('timeSeconds')
          .limit(leaderboardSize)
          .get();
      return snap.docs.map(TrueFanScoreEntry.fromDoc).toList();
    });
  }

  /// The signed-in user's own passed entry for [anilistId], or null.
  Future<TrueFanScoreEntry?> myEntry(int anilistId) {
    return _guard('myEntry($anilistId)', () async {
      final uid = (await AuthService.instance.initAuth()).uid;
      final doc = await _scores.doc(_docId(uid, anilistId)).get();
      if (!doc.exists || doc.data()?['passed'] != true) return null;
      return TrueFanScoreEntry.fromDoc(doc);
    });
  }

  /// Exact leaderboard rank for a passed run of [timeSeconds]: a count()
  /// aggregation of strictly faster passed runs, plus one. Scope to a country
  /// with [countryCode] (Local tab); null means worldwide.
  Future<int> rankForTime(int anilistId, double timeSeconds, {String? countryCode}) {
    return _guard('rankForTime($anilistId, $countryCode)', () async {
      final agg = await _passedQuery(anilistId, countryCode: countryCode)
          .where('timeSeconds', isLessThan: timeSeconds)
          .count()
          .get();
      return (agg.count ?? 0) + 1;
    });
  }
}
