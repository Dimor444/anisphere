import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/true_fan_profile_service.dart';
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

/// Owner-credential seed of another user's passed score — bypasses rules,
/// exactly how backfill/admin tooling would write.
Future<void> _seedScore({
  required String userId,
  required int anilistId,
  required double timeSeconds,
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
        'countryCode': {'stringValue': 'US'},
        'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed score failed: ${res.body}');
}

/// Full owner-credential dump of trueFanScores (names + updateTimes + fields),
/// used to prove the profile feature performed NO writes.
Future<String> _collectionSnapshot() async {
  final res = await http.get(Uri.parse('$_base/trueFanScores?pageSize=300'), headers: _ownerHeaders);
  expect(res.statusCode, 200, reason: 'collection dump failed: ${res.body}');
  return res.body;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Distinct id range from true_fan_scores_test (990001+) so runs never bleed.
  const alphaAnime = 970001; // seeds 10/20/30s, me 15s   → rank 2
  const betaAnime = 970002; //  seeds 5/6s,      me 4.2s  → rank 1
  const gammaAnime = 970003; // seeds 1..5s,     me 100s  → rank 6

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('service: my passes come back with hand-calculated global ranks, read-only',
      (tester) async {
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZTrueFanProfile');

    // Other users' scores around mine, at known times.
    for (final t in [10.0, 20.0, 30.0]) {
      await _seedScore(userId: 'zzalpha${t.round()}', anilistId: alphaAnime, timeSeconds: t);
    }
    for (final t in [5.0, 6.0]) {
      await _seedScore(userId: 'zzbeta${t.round()}', anilistId: betaAnime, timeSeconds: t);
    }
    for (var t = 1; t <= 5; t++) {
      await _seedScore(userId: 'zzgamma$t', anilistId: gammaAnime, timeSeconds: t.toDouble());
    }

    // My passes go through the real challenge write path.
    final svc = TrueFanScoreService.instance;
    expect(await svc.submitPass(anilistId: alphaAnime, animeTitle: 'ZZ Alpha', score: 8, timeSeconds: 15.0), isTrue);
    expect(await svc.submitPass(anilistId: betaAnime, animeTitle: 'ZZ Beta', score: 9, timeSeconds: 4.2), isTrue);
    expect(await svc.submitPass(anilistId: gammaAnime, animeTitle: 'ZZ Gamma', score: 7, timeSeconds: 100.0), isTrue);

    final before = await _collectionSnapshot();
    final entries = await TrueFanProfileService.instance.fetchMyEntries();

    for (final e in entries) {
      debugPrint('[true_fan_profile_test] {anilistId: ${e.anilistId}, '
          'rank: ${e.rank}, timeSeconds: ${e.timeSeconds}} title="${e.title}"');
    }

    // Hand-calculated positions, sorted best rank first.
    expect(entries.length, 3);
    expect(entries[0].anilistId, betaAnime);
    expect(entries[0].rank, 1, reason: 'nobody faster than 4.2s on beta');
    expect(entries[0].timeSeconds, 4.2);
    expect(entries[1].anilistId, alphaAnime);
    expect(entries[1].rank, 2, reason: 'only the 10s seed beats my 15s on alpha');
    expect(entries[1].timeSeconds, 15.0);
    expect(entries[2].anilistId, gammaAnime);
    expect(entries[2].rank, 6, reason: 'all five 1..5s seeds beat my 100s on gamma');
    expect(entries[2].timeSeconds, 100.0);

    // Fake ids never resolve on AniList → titles fall back to the stored
    // animeTitle; anime metadata is never written to Firestore.
    expect(entries[0].title, 'ZZ Beta');
    expect(entries[1].title, 'ZZ Alpha');
    expect(entries[2].title, 'ZZ Gamma');

    // Display-only: the fetch left every score doc byte-for-byte untouched.
    expect(await _collectionSnapshot(), before, reason: 'fetchMyEntries must not write');
  });

  testWidgets('profile UI: 🏆 section lists ranked passes, chip shows the count',
      (tester) async {
    // Same signed-in user as above — 3 passes already recorded.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    await pumpUntil(tester, find.text('🏆 3 True Fan'));
    expect(find.text('🏆 True Fan'), findsOneWidget); // section header
    // Cards carry the real global ranks and times, best rank first.
    await pumpUntil(tester, find.text('#1'));
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#6'), findsOneWidget);
    expect(find.text('ZZ Beta'), findsOneWidget);
    expect(find.text('⏱ 4.200s'), findsOneWidget);
    // The old sample rank never appears on the own profile.
    expect(find.text('🌍 True Fan #847'), findsNothing);
  });

  testWidgets('profile UI: empty state shows the friendly prompt, never a broken box',
      (tester) async {
    // Fresh user with zero passes.
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZNoPasses');

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    await pumpUntil(tester, find.text('🏆 0 True Fan'));
    await pumpUntil(tester, find.textContaining('No True Fan titles yet'));
    expect(find.text('🌍 True Fan #847'), findsNothing);
  });
}
