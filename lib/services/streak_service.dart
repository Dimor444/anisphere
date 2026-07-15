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

  /// Forget the session memo so the next [checkIn] re-reads the doc.
  @visibleForTesting
  void resetSession() => _sessionDay = null;

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
