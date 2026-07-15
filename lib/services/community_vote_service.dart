import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/community_vote.dart';
import 'auth_service.dart';

/// The user has no votes left today.
class VoteLimitReachedException implements Exception {}

/// The user already voted for this anime today (same anime on a LATER day
/// is fine — dayId differs).
class AlreadyVotedTodayException implements Exception {}

/// AniSphere's own daily "favorite anime" poll — fully separate from the
/// AniList-backed Top 100 chart.
///
/// Day boundary is 00:00 UTC for everyone (dayId "YYYY-MM-DD"), so a new day
/// simply reads/writes a different subcollection — no reset action exists.
/// Free users get 1 vote/day, AniPlus 4. Votes are FINAL: this service
/// exposes no retract/update path and security rules deny update/delete on
/// vote docs. Tallies are bumped +1 in the vote batch (rules-capped) until
/// Cloud Functions take over; the same-anime-same-day check is client-side
/// until then.
class CommunityVoteService {
  CommunityVoteService._();
  static final CommunityVoteService instance = CommunityVoteService._();

  static const int freeVotes = 1;
  static const int plusVotes = 4;
  static const int maxSlot = 4;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  CollectionReference<Map<String, dynamic>> _votes(String dayId) =>
      _db.collection('community_votes').doc(dayId).collection('votes');
  CollectionReference<Map<String, dynamic>> _tally(String dayId) =>
      _db.collection('community_votes').doc(dayId).collection('tally');

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[CommunityVoteService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[CommunityVoteService] $op failed: $e');
      rethrow;
    }
  }

  // ── Day math (pure, testable) ──────────────────────────────────────────

  /// "YYYY-MM-DD" for [when] in UTC.
  static String dayIdFor(DateTime when) {
    final utc = when.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  String getCurrentDayId() => dayIdFor(DateTime.now());

  /// Time left until the next 00:00 UTC reset, seen from [when].
  static Duration untilNextResetFrom(DateTime when) {
    final utc = when.toUtc();
    final nextMidnight = DateTime.utc(utc.year, utc.month, utc.day).add(const Duration(days: 1));
    return nextMidnight.difference(utc);
  }

  Duration untilNextReset() => untilNextResetFrom(DateTime.now());

  static int getMaxVotesForUser({required bool isPlus}) => isPlus ? plusVotes : freeVotes;

  // ── Reads ──────────────────────────────────────────────────────────────

  /// The signed-in user's votes for today, slot order. Live.
  Stream<List<CommunityVote>> getUserVotesToday() async* {
    final uid = await _uid();
    yield* _votes(getCurrentDayId()).where('userId', isEqualTo: uid).snapshots().map((snap) {
      final votes = snap.docs.map(CommunityVote.fromDoc).toList()
        ..sort((a, b) => a.voteSlot.compareTo(b.voteSlot));
      return votes;
    });
  }

  Future<List<CommunityVote>> _votesTodayOnce() async {
    final uid = await _uid();
    final snap = await _votes(getCurrentDayId()).where('userId', isEqualTo: uid).get();
    return snap.docs.map(CommunityVote.fromDoc).toList();
  }

  Future<int> getRemainingVotes({required bool isPlus}) {
    return _guard('remaining', () async {
      final used = (await _votesTodayOnce()).length;
      return (getMaxVotesForUser(isPlus: isPlus) - used).clamp(0, maxSlot);
    });
  }

  Future<bool> hasUserVotedForAnime(int anilistId, {String? dayId}) {
    return _guard('hasVoted($anilistId)', () async {
      final uid = await _uid();
      final snap = await _votes(dayId ?? getCurrentDayId())
          .where('userId', isEqualTo: uid)
          .where('anilist_id', isEqualTo: anilistId)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    });
  }

  /// Live ranked results for [dayId] (today's board), most votes first.
  Stream<List<CommunityVoteTally>> getDailyLeaderboard({String? dayId, int limit = 50}) =>
      _tally(dayId ?? getCurrentDayId())
          .orderBy('voteCount', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(CommunityVoteTally.fromDoc).toList());

  /// One-shot final results of a past day (history/archive view). Past days
  /// are immutable by construction — nothing writes to an old dayId.
  Future<List<CommunityVoteTally>> getPastDayLeaderboard(String dayId, {int limit = 50}) {
    return _guard('pastDay($dayId)', () async {
      final snap =
          await _tally(dayId).orderBy('voteCount', descending: true).limit(limit).get();
      return snap.docs.map(CommunityVoteTally.fromDoc).toList();
    });
  }

  // ── The one write ──────────────────────────────────────────────────────

  /// Cast a FINAL vote. Throws [AlreadyVotedTodayException] /
  /// [VoteLimitReachedException] before writing anything. There is
  /// deliberately no retract/update counterpart — rules deny those too.
  Future<void> castVote({
    required int anilistId,
    required String animeTitle,
    String animeCover = '',
    required bool isPlus,
  }) {
    return _guard('castVote($anilistId)', () async {
      final uid = await _uid();
      final dayId = getCurrentDayId();
      final existing = await _votesTodayOnce();

      if (existing.any((v) => v.anilistId == anilistId)) throw AlreadyVotedTodayException();
      if (existing.length >= getMaxVotesForUser(isPlus: isPlus)) throw VoteLimitReachedException();

      // Next free slot (slots are doc-id-unique, so a race just fails create).
      final taken = existing.map((v) => v.voteSlot).toSet();
      final slot = List.generate(maxSlot, (i) => i + 1).firstWhere((s) => !taken.contains(s));

      final vote = CommunityVote(
        userId: uid,
        anilistId: anilistId,
        animeTitle: animeTitle,
        animeCover: animeCover,
        dayId: dayId,
        voteSlot: slot,
      );
      final batch = _db.batch()
        ..set(_votes(dayId).doc(vote.docId), vote.toMap())
        ..set(
          _tally(dayId).doc('$anilistId'),
          {
            'anilist_id': anilistId,
            'animeTitle': animeTitle,
            'animeCover': animeCover,
            'dayId': dayId,
            'voteCount': FieldValue.increment(1),
          },
          SetOptions(merge: true),
        );
      await batch.commit();
    });
  }
}
