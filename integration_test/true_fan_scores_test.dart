import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/features/challenges/true_fan_leaderboard.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/true_fan_score_service.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

const _base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
const _ownerHeaders = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

/// Owner-credential seed of a passed score for a fake user — bypasses rules,
/// exactly how backfill/admin tooling would write.
Future<void> _seedScore({
  required String userId,
  required int anilistId,
  required double timeSeconds,
  required String countryCode,
  int score = 8,
}) async {
  final res = await http.patch(
    Uri.parse('$_base/trueFanScores/${userId}_$anilistId'),
    headers: _ownerHeaders,
    body: jsonEncode({
      'fields': {
        'userId': {'stringValue': userId},
        'anilistId': {'integerValue': '$anilistId'},
        'animeTitle': {'stringValue': 'ZZ Seed Anime'},
        'passed': {'booleanValue': true},
        'score': {'integerValue': '$score'},
        'timeSeconds': {'doubleValue': timeSeconds},
        'userName': {'stringValue': userId},
        'userAvatar': {'stringValue': ''},
        'countryCode': {'stringValue': countryCode},
        'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed score failed: ${res.body}');
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final svc = TrueFanScoreService.instance;
  late String uid;

  // Distinct anime ids per scenario so boards don't bleed into each other.
  const upsertAnime = 990001;
  const bigBoardAnime = 990002; // 50 JP + 10 US seeds, user slowest
  const smallBoardAnime = 990003; // user + 10 slower seeds — user visible inline
  const foreignAnime = 990004; // only FR passes — Local (JP) empty
  const emptyAnime = 990005; // nobody passed

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

    await AuthService.instance.signOut();
    uid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZTrueFan');
    // Pin the country so Local-tab assertions are deterministic regardless of
    // the simulator's locale.
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'countryCode': 'JP'});
  });

  testWidgets('profile: ensureProfile caches a plausible countryCode', (tester) async {
    // A fresh doc got SOME auto-detected value before we pinned it — the rules
    // and model accept 2-3 chars; re-running ensureProfile must not overwrite
    // the cached (pinned) value.
    await FollowService.instance.ensureProfile(userName: 'ZZTrueFan');
    final profile = await FollowService.instance.getUser(uid);
    expect(profile, isNotNull);
    expect(profile!.countryCode, 'JP', reason: 'countryCode is detected once, never re-detected');
  });

  testWidgets('service: only passes are written, best time is kept', (tester) async {
    // Below the pass bar → no write.
    expect(await svc.submitPass(anilistId: upsertAnime, animeTitle: 'ZZ', score: 6, timeSeconds: 10), isFalse);
    expect(await svc.myEntry(upsertAnime), isNull);

    // First pass → written with denormalized profile fields.
    expect(await svc.submitPass(anilistId: upsertAnime, animeTitle: 'ZZ', score: 8, timeSeconds: 42.5), isTrue);
    var mine = await svc.myEntry(upsertAnime);
    expect(mine, isNotNull);
    expect(mine!.timeSeconds, 42.5);
    expect(mine.countryCode, 'JP');
    expect(mine.userName, 'ZZTrueFan');

    // Slower pass → keeps the stored best.
    expect(await svc.submitPass(anilistId: upsertAnime, animeTitle: 'ZZ', score: 10, timeSeconds: 50), isFalse);
    mine = await svc.myEntry(upsertAnime);
    expect(mine!.timeSeconds, 42.5);

    // Faster pass → upserts.
    expect(await svc.submitPass(anilistId: upsertAnime, animeTitle: 'ZZ', score: 7, timeSeconds: 30), isTrue);
    mine = await svc.myEntry(upsertAnime);
    expect(mine!.timeSeconds, 30);
    expect(mine.score, 7);
  });

  testWidgets('rules: forged or failing score docs are rejected', (tester) async {
    final scores = FirebaseFirestore.instance.collection('trueFanScores');
    Map<String, dynamic> payload({String? forUid, bool passed = true}) => {
          'userId': forUid ?? uid,
          'anilistId': 990099,
          'animeTitle': 'ZZ',
          'passed': passed,
          'score': 9,
          'timeSeconds': 12.0,
          'userName': 'ZZTrueFan',
          'userAvatar': '',
          'countryCode': 'JP',
          'updatedAt': FieldValue.serverTimestamp(),
        };

    // passed: false is never accepted.
    await expectLater(
      scores.doc('${uid}_990099').set(payload(passed: false)),
      throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')),
    );
    // Writing under someone else's uid is never accepted.
    await expectLater(
      scores.doc('zzother_990099').set(payload(forUid: 'zzother')),
      throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')),
    );
    // Doc id must be {uid}_{anilistId}.
    await expectLater(
      scores.doc('${uid}_123').set(payload()),
      throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')),
    );
    // Well-formed self-owned pass → accepted.
    await scores.doc('${uid}_990099').set(payload());
  });

  testWidgets('queries: top 44 + exact rank, global and country-scoped', (tester) async {
    for (var i = 1; i <= 50; i++) {
      await _seedScore(userId: 'zzjp$i', anilistId: bigBoardAnime, timeSeconds: i.toDouble(), countryCode: 'JP');
    }
    for (var i = 1; i <= 10; i++) {
      await _seedScore(userId: 'zzus$i', anilistId: bigBoardAnime, timeSeconds: 50 + i.toDouble(), countryCode: 'US');
    }
    // The signed-in user passes, slower than everyone.
    expect(await svc.submitPass(anilistId: bigBoardAnime, animeTitle: 'ZZ', score: 9, timeSeconds: 999), isTrue);

    final global = await svc.topScores(bigBoardAnime);
    expect(global.length, TrueFanScoreService.leaderboardSize);
    expect(global.first.timeSeconds, 1.0);
    expect(global.last.timeSeconds, 44.0);
    expect(global.map((e) => e.userId), isNot(contains(uid)));

    final local = await svc.topScores(bigBoardAnime, countryCode: 'JP');
    expect(local.length, TrueFanScoreService.leaderboardSize);
    expect(local.every((e) => e.countryCode == 'JP'), isTrue);

    // 60 faster worldwide → #61; 50 faster in JP → #51.
    expect(await svc.rankForTime(bigBoardAnime, 999), 61);
    expect(await svc.rankForTime(bigBoardAnime, 999, countryCode: 'JP'), 51);
  });

  testWidgets('widget: You:#N below the fold on Global and Local', (tester) async {
    await tester.pumpWidget(_host(const TrueFanLeaderboard(anilistId: bigBoardAnime)));
    await pumpUntil(tester, find.text('You: #61'));
    expect(find.text('🌍 Global'), findsOneWidget);
    expect(find.text('zzjp1'), findsOneWidget); // fastest seed visible

    await tester.tap(find.text('📍 Local'));
    await pumpUntil(tester, find.text('You: #51'));
    expect(find.text('You: #61'), findsNothing);
  });

  testWidgets('widget: inside the top 44 → inline highlight, no You row', (tester) async {
    expect(await svc.submitPass(anilistId: smallBoardAnime, animeTitle: 'ZZ', score: 10, timeSeconds: 5), isTrue);
    for (var i = 1; i <= 10; i++) {
      await _seedScore(userId: 'zzslow$i', anilistId: smallBoardAnime, timeSeconds: 10 + i.toDouble(), countryCode: 'US');
    }

    await tester.pumpWidget(_host(const TrueFanLeaderboard(anilistId: smallBoardAnime)));
    await pumpUntil(tester, find.text('ZZTrueFan (you)'));
    expect(find.textContaining('You: #'), findsNothing);
  });

  testWidgets('widget: Local empty state when only other countries passed', (tester) async {
    for (var i = 1; i <= 3; i++) {
      await _seedScore(userId: 'zzfr$i', anilistId: foreignAnime, timeSeconds: i.toDouble(), countryCode: 'FR');
    }

    await tester.pumpWidget(_host(const TrueFanLeaderboard(anilistId: foreignAnime)));
    await pumpUntil(tester, find.text('zzfr1'));
    await tester.tap(find.text('📍 Local'));
    await pumpUntil(tester, find.textContaining('Nobody from your country'));
  });

  testWidgets('widget: global empty state and unresolved-id note', (tester) async {
    await tester.pumpWidget(_host(const TrueFanLeaderboard(anilistId: emptyAnime)));
    await pumpUntil(tester, find.textContaining('No one has passed'));

    await tester.pumpWidget(_host(const TrueFanLeaderboard(anilistId: null)));
    await tester.pump();
    expect(find.textContaining('Leaderboard unavailable'), findsOneWidget);
  });
}
