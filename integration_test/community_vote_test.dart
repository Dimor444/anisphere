import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/community_vote_service.dart';
import 'package:anisphere/services/follow_service.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Owner-credential writes through the emulator REST API — used to seed a
/// PAST day, which clients can't (and shouldn't) write via the SDK.
Future<void> _seedPastDay(String dayId, String uid, int animeId, String title, int tallyCount) async {
  const base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
  final headers = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};
  var res = await http.patch(
    Uri.parse('$base/community_votes/$dayId/votes/${uid}_1'),
    headers: headers,
    body: jsonEncode({
      'fields': {
        'userId': {'stringValue': uid},
        'anilist_id': {'integerValue': '$animeId'},
        'animeTitle': {'stringValue': title},
        'animeCover': {'stringValue': ''},
        'dayId': {'stringValue': dayId},
        'voteSlot': {'integerValue': '1'},
        'votedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed vote failed: ${res.body}');
  res = await http.patch(
    Uri.parse('$base/community_votes/$dayId/tally/$animeId'),
    headers: headers,
    body: jsonEncode({
      'fields': {
        'anilist_id': {'integerValue': '$animeId'},
        'animeTitle': {'stringValue': title},
        'animeCover': {'stringValue': ''},
        'dayId': {'stringValue': dayId},
        'voteCount': {'integerValue': '$tallyCount'},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed tally failed: ${res.body}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final svc = CommunityVoteService.instance;
  late String freeUid;
  late String plusUid;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('service: free user gets exactly one FINAL vote', (tester) async {
    await AuthService.instance.signOut();
    freeUid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZVoterFree');

    expect(await svc.getRemainingVotes(isPlus: false), 1);
    await svc.castVote(anilistId: 900001, animeTitle: 'ZZVote Anime 1', isPlus: false);

    final votes = await svc.getUserVotesToday().first;
    expect(votes.length, 1);
    expect(votes.single.voteSlot, 1);
    expect(votes.single.anilistId, 900001);
    expect(await svc.hasUserVotedForAnime(900001), isTrue);
    expect(await svc.getRemainingVotes(isPlus: false), 0);

    // Same anime again today → blocked as duplicate.
    await expectLater(
      svc.castVote(anilistId: 900001, animeTitle: 'ZZVote Anime 1', isPlus: false),
      throwsA(isA<AlreadyVotedTodayException>()),
    );
    // A different anime → blocked by the 1-vote limit.
    await expectLater(
      svc.castVote(anilistId: 900002, animeTitle: 'ZZVote Anime 2', isPlus: false),
      throwsA(isA<VoteLimitReachedException>()),
    );

    final dayId = svc.getCurrentDayId();
    final voteRef = FirebaseFirestore.instance
        .collection('community_votes')
        .doc(dayId)
        .collection('votes')
        .doc('${freeUid}_1');
    // Votes are permanent: rules reject deletes and edits outright.
    await expectLater(voteRef.delete(), throwsA(isA<FirebaseException>()));
    await expectLater(voteRef.update({'anilist_id': 123}), throwsA(isA<FirebaseException>()));
    // Free users can't sneak a Plus slot past the rules either.
    await expectLater(
      FirebaseFirestore.instance
          .collection('community_votes')
          .doc(dayId)
          .collection('votes')
          .doc('${freeUid}_2')
          .set({
        'userId': freeUid,
        'anilist_id': 900002,
        'animeTitle': 'ZZVote Anime 2',
        'animeCover': '',
        'dayId': dayId,
        'voteSlot': 2,
        'votedAt': FieldValue.serverTimestamp(),
      }),
      throwsA(isA<FirebaseException>()),
    );
  });

  testWidgets('service: AniPlus user gets four votes, no dupes, hard cap', (tester) async {
    await AuthService.instance.signOut();
    plusUid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZVoterPlus', isPlus: true);

    for (var i = 1; i <= 4; i++) {
      await svc.castVote(anilistId: 900000 + i, animeTitle: 'ZZVote Anime $i', isPlus: true);
    }
    expect((await svc.getUserVotesToday().first).length, 4);
    expect(await svc.getRemainingVotes(isPlus: true), 0);

    await expectLater(
      svc.castVote(anilistId: 900005, animeTitle: 'ZZVote Anime 5', isPlus: true),
      throwsA(isA<VoteLimitReachedException>()),
    );
    await expectLater(
      svc.castVote(anilistId: 900002, animeTitle: 'ZZVote Anime 2', isPlus: true),
      throwsA(isA<AlreadyVotedTodayException>()),
    );

    // Leaderboard: anime 1 has votes from both users and leads. Counts are
    // lower-bounded, not exact — emulator state accumulates across runs.
    final board = await svc.getDailyLeaderboard().first;
    expect(board.first.anilistId, 900001);
    expect(board.first.voteCount, greaterThanOrEqualTo(2));
    expect(board.length, greaterThanOrEqualTo(4));
  });

  testWidgets('service: past days are viewable; same anime OK on a new day', (tester) async {
    final yesterday = CommunityVoteService.dayIdFor(
        DateTime.now().toUtc().subtract(const Duration(days: 1)));
    // The (still signed-in) Plus user voted for anime 900002 "yesterday" AND
    // today (test 2) — the same anime across different days is allowed.
    await _seedPastDay(yesterday, plusUid, 900002, 'ZZVote Anime 2', 3);

    final past = await svc.getPastDayLeaderboard(yesterday);
    expect(past, isNotEmpty);
    expect(past.first.anilistId, 900002);
    expect(past.first.voteCount, 3);

    expect(await svc.hasUserVotedForAnime(900002, dayId: yesterday), isTrue);
    expect(await svc.hasUserVotedForAnime(900002), isTrue, reason: 'today too');
    // Today's board is untouched by yesterday's tally of 3.
    final today = await svc.getDailyLeaderboard().first;
    final todayCount = today.firstWhere((t) => t.anilistId == 900002).voteCount;
    expect(todayCount, lessThan(3), reason: 'yesterday must not bleed into today');
  });

  testWidgets('ui: vote tab, cast flow with confirmation, live board, limits', (tester) async {
    // Fresh user for the UI run; MainShell mirrors the sample session
    // (AniPlus) into the profile, so 4 slots are available.
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/discover');

    await pumpUntil(tester, find.text('🗳️ Vote'));
    await tester.ensureVisible(find.text('🗳️ Vote'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('🗳️ Vote'));

    await pumpUntil(tester, find.textContaining("Community Vote"));
    await pumpUntil(tester, find.textContaining('Resets in'));
    await pumpUntil(tester, find.textContaining('Votes remaining: 4/4'));
    // Leaderboard is live from the earlier service tests.
    await pumpUntil(tester, find.textContaining('ZZVote Anime 1'));

    // Cast a real vote through the sheet (live AniList search).
    await tester.tap(find.text('Cast a Vote'));
    await pumpUntil(tester, find.byKey(const ValueKey('vote-search')));
    await tester.enterText(find.byKey(const ValueKey('vote-search')), 'frieren');
    await pumpUntil(tester, find.textContaining('Frieren'));
    await tester.tap(find.textContaining('Frieren').first);

    // Irreversibility is spelled out before anything is written.
    await pumpUntil(tester, find.textContaining("can't be undone"));
    await tester.tap(find.text('Vote'));
    await pumpUntil(tester, find.textContaining('Vote cast!'));

    // Status, own-votes list and leaderboard all update in real time.
    await pumpUntil(tester, find.textContaining('Votes remaining: 3/4'));
    await pumpUntil(tester, find.text('Your Votes Today'));
    expect(find.textContaining('Frieren'), findsWidgets);
  });
}
