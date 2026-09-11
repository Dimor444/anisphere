import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'community_vote_service.dart';

/// Daily login streak — "activity" is simply opening the app.
///
/// Day boundary is 00:00 UTC ("YYYY-MM-DD" via [CommunityVoteService.dayIdFor],
/// the same reset pattern as the Community Vote). The first open of a UTC day
/// writes currentStreak/longestStreak/lastActiveDay on `users/{uid}`; any
/// further opens or resumes that day write nothing. Security rules only admit
/// streak-only writes that +1 or reset, stamped with the server's UTC day, so
/// the value can't be forged or replayed.
class StreakService {
  StreakService._();
  static final StreakService instance = StreakService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// UTC day this session already checked in (or confirmed as checked-in) —
  /// resumes within the same day skip even the read.
  String? _sessionDay;
  Future<bool>? _inFlight;

  /// Forget both memos so the next [checkIn] re-reads the doc.
  ///
  /// Called by SessionLifecycle when the signed-in identity changes. Both
  /// fields record something about THIS PROCESS and neither records WHOSE, so
  /// both hand the next user the previous user's answer:
  ///
  /// - [_sessionDay] — "this process already checked in today". Left set, the
  ///   next user's first [checkIn] takes the early return and they never get a
  ///   first check-in until the process restarts.
  /// - [_inFlight] — the check-in currently running. Left set, `_inFlight ??=`
  ///   hands the next user the PREVIOUS user's future, so their own check-in
  ///   never starts and they receive a result computed for someone else.
  ///
  /// Nulling [_inFlight] does not cancel the run it referenced — Dart futures
  /// have no cancellation, and this only drops our handle on it. That run is
  /// harmless: it captured its own uid before its first await, so it can only
  /// ever write ITS OWN doc, and its single merge-set is atomic at the
  /// document level. After a sign-out it simply fails (initAuth refuses, or
  /// the write is denied), and its own catch swallows that and returns false.
  ///
  /// No longer @visibleForTesting: production calls it now, and keeping the
  /// annotation makes that call an `invalid_use_of_visible_for_testing_member`
  /// warning. It is the same shape as FollowService.resetForSignOut, which is
  /// likewise a plain public method the lifecycle calls.
  void resetSession() {
    _sessionDay = null;
    _inFlight = null;
  }

  /// What the streak chip should SHOW right now — read-only, never writes.
  ///
  /// The stored currentStreak goes stale between opens (there is no decay
  /// job): a streak is only displayed while it's still alive, i.e. the last
  /// check-in was today or yesterday (UTC). Anything older (or no check-in
  /// yet) displays as 0; the stored value is left for the next real
  /// [checkIn] to reset or extend.
  static int displayStreak({
    required int currentStreak,
    required String lastActiveDay,
    DateTime? now,
  }) {
    final ref = (now ?? DateTime.now()).toUtc();
    final today = CommunityVoteService.dayIdFor(ref);
    final yesterday = CommunityVoteService.dayIdFor(ref.subtract(const Duration(days: 1)));
    return (lastActiveDay == today || lastActiveDay == yesterday) ? currentStreak : 0;
  }

  /// Record today's check-in if it hasn't happened yet. Returns true when a
  /// write happened (first open of this UTC day). Never throws — a failed
  /// streak write must never crash the app or block the UI.
  Future<bool> checkIn() {
    final today = CommunityVoteService.dayIdFor(DateTime.now());
    if (_sessionDay == today) return Future.value(false);
    return _inFlight ??= _checkIn(today).whenComplete(() => _inFlight = null);
  }

  Future<bool> _checkIn(String today) async {
    try {
      final uid = (await AuthService.instance.initAuth()).uid;
      final doc = _db.collection('users').doc(uid);
      final snap = await doc.get();
      // Profile not created yet (ensureProfile failed?) — retry next open.
      if (!snap.exists) return false;

      final d = snap.data() ?? const <String, dynamic>{};
      final last = d['lastActiveDay'] as String? ?? '';
      final current = (d['currentStreak'] as num?)?.toInt() ?? 0;
      final longest = (d['longestStreak'] as num?)?.toInt() ?? 0;
      debugPrint('[StreakService] users/$uid before check-in — '
          'currentStreak: $current, longestStreak: $longest, lastActiveDay: "$last" (today: $today)');

      if (last == today) {
        _sessionDay = today;
        debugPrint('[StreakService] already checked in today — no write');
        return false;
      }

      final yesterday =
          CommunityVoteService.dayIdFor(DateTime.now().toUtc().subtract(const Duration(days: 1)));
      final newStreak = last == yesterday ? current + 1 : 1; // gap or first ever resets
      final newLongest = newStreak > longest ? newStreak : longest;

      await doc.set({
        'currentStreak': newStreak,
        'longestStreak': newLongest,
        'lastActiveDay': today,
      }, SetOptions(merge: true));
      _sessionDay = today;
      debugPrint('[StreakService] users/$uid after check-in — '
          'currentStreak: $newStreak, longestStreak: $newLongest, lastActiveDay: "$today"');
      return true;
    } catch (e) {
      debugPrint('[StreakService] checkIn failed: $e');
      return false;
    }
  }
}
