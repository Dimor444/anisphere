import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/features/profile/user_profile_screen.dart';
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

final _denied = throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'));

/// Owner-credential purge of every score doc for [anilistId], so reruns of
/// this suite (and earlier failed runs) can't skew the hand-calculated ranks.
Future<void> _purgeAnime(int anilistId) async {
  final res = await http.post(
    Uri.parse('$_base:runQuery'),
    headers: _ownerHeaders,
    body: jsonEncode({
      'structuredQuery': {
        'from': [{'collectionId': 'trueFanScores'}],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': 'anilistId'},
            'op': 'EQUAL',
            'value': {'integerValue': '$anilistId'},
          },
        },
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'purge query failed: ${res.body}');
  for (final row in jsonDecode(res.body) as List<dynamic>) {
    final name = (row as Map<String, dynamic>)['document']?['name'] as String?;
    if (name == null) continue;
    final del = await http.delete(
      Uri.parse('http://localhost:8080/v1/$name'),
      headers: _ownerHeaders,
    );
    expect(del.statusCode, 200, reason: 'purge delete failed: ${del.body}');
  }
}

Future<void> _seedScore(String userId, int anilistId, double timeSeconds) async {
  final res = await http.patch(
    Uri.parse('$_base/trueFanScores/${userId}_$anilistId'),
    headers: _ownerHeaders,
    body: jsonEncode({
      'fields': {
        'userId': {'stringValue': userId},
        'anilistId': {'integerValue': '$anilistId'},
        'animeTitle': {'stringValue': 'ZZ Seed Anime'},
        'passed': {'booleanValue': true},
        'score': {'integerValue': '8'},
        'timeSeconds': {'doubleValue': timeSeconds},
        'userName': {'stringValue': userId},
        'userAvatar': {'stringValue': ''},
        'countryCode': {'stringValue': 'US'},
        'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed failed: ${res.body}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Distinct id range from the other suites so runs never bleed.
  const hideMe = 960001; // seeds 5s/10s, owner 7.5s → rank 2; gets hidden
  const keepMe = 960002; // owner alone at 3.0s → rank 1; stays visible

  late String ownerUid;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await _purgeAnime(hideMe);
    await _purgeAnime(keepMe);
  });

  testWidgets('owner: setHidden flips only the flag; rank and leaderboard unchanged',
      (tester) async {
    await AuthService.instance.signOut();
    ownerUid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZHideOwner');

    await _seedScore('zzfast', hideMe, 5.0);
    await _seedScore('zzslow', hideMe, 10.0);
    final scoreSvc = TrueFanScoreService.instance;
    expect(await scoreSvc.submitPass(anilistId: hideMe, animeTitle: 'ZZ Hide Me', score: 8, timeSeconds: 7.5), isTrue);
    expect(await scoreSvc.submitPass(anilistId: keepMe, animeTitle: 'ZZ Keep Me', score: 9, timeSeconds: 3.0), isTrue);

    final doc = FirebaseFirestore.instance.collection('trueFanScores').doc('${ownerUid}_$hideMe');
    final before = (await doc.get()).data()!;
    final rankBefore = await scoreSvc.rankForTime(hideMe, 7.5);
    expect(rankBefore, 2, reason: 'only the 5s seed is faster');

    await TrueFanProfileService.instance.setHidden(anilistId: hideMe, hidden: true);

    final after = (await doc.get()).data()!;
    debugPrint('[hide_test] after setHidden: hiddenFromProfile=${after['hiddenFromProfile']}, '
        'timeSeconds=${after['timeSeconds']}, passed=${after['passed']}, score=${after['score']}');
    expect(after['hiddenFromProfile'], isTrue);
    // Every other field is byte-identical — hide is display-only.
    for (final k in before.keys) {
      expect(after[k], before[k], reason: 'setHidden must not touch "$k"');
    }

    // Owner still sees BOTH entries, the hidden one flagged.
    final mine = await TrueFanProfileService.instance.fetchMyEntries();
    for (final e in mine) {
      debugPrint('[hide_test] owner entry {anilistId: ${e.anilistId}, rank: ${e.rank}, '
          'timeSeconds: ${e.timeSeconds}, hidden: ${e.hidden}}');
    }
    expect(mine.length, 2);
    expect(mine.singleWhere((e) => e.anilistId == hideMe).hidden, isTrue);
    expect(mine.singleWhere((e) => e.anilistId == keepMe).hidden, isFalse);

    // The hidden score still counts on the anime's leaderboard.
    expect(await scoreSvc.rankForTime(hideMe, 7.5), rankBefore,
        reason: 'hide never removes the score from ranking');
    final board = await scoreSvc.topScores(hideMe);
    expect(board.map((e) => e.userId), contains(ownerUid),
        reason: 'hidden entry still on the leaderboard');
    debugPrint('[hide_test] leaderboard for $hideMe still ranks owner at #$rankBefore '
        'with ${board.length} rows');
  });

  testWidgets('rules: owner cannot smuggle score changes through the toggle', (tester) async {
    final doc = FirebaseFirestore.instance.collection('trueFanScores').doc('${ownerUid}_$hideMe');

    // Toggle + immutable field in one write → denied (the hide branch only
    // accepts a hiddenFromProfile-shaped diff, and the full-payload branch
    // rejects the 11-key result).
    await expectLater(doc.update({'hiddenFromProfile': false, 'timeSeconds': 0.1}), _denied);
    await expectLater(doc.update({'hiddenFromProfile': false, 'passed': false}), _denied);
    await expectLater(doc.update({'hiddenFromProfile': false, 'score': 10}), _denied);
    // Immutable field alone on this (hidden) doc → denied: the merged doc
    // carries hiddenFromProfile, so it no longer matches the 10-key score
    // payload either. (On docs without the flag, an owner self-overwrite in
    // the full valid-payload shape remains allowed — that IS the challenge's
    // pre-existing improve-your-time upsert path, untouched here.)
    await expectLater(doc.update({'timeSeconds': 0.1}), _denied);
    // Wrong type → denied.
    await expectLater(doc.update({'hiddenFromProfile': 'yes'}), _denied);

    final d = (await doc.get()).data()!;
    expect(d['timeSeconds'], 7.5);
    expect(d['passed'], true);
    expect(d['hiddenFromProfile'], true);
    debugPrint('[hide_test] all forged toggle writes denied; doc unchanged');
  });

  testWidgets('owner UI: hidden card is marked, chip keeps the true total, eye toggles',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    // Chip counts ALL passes (hidden included) on the owner's own profile.
    await pumpUntil(tester, find.text('🏆 2 True Fan'));
    await pumpUntil(tester, find.text('ZZ Hide Me'));
    expect(find.text('ZZ Keep Me'), findsOneWidget);
    expect(find.text('Hidden'), findsOneWidget); // pill on the hidden card only
    expect(find.byIcon(LucideIcons.eyeOff), findsWidgets);

    // Scroll the rail into tap range, then hide "ZZ Keep Me" via its eye.
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(LucideIcons.eye).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));

    final keepDoc = FirebaseFirestore.instance.collection('trueFanScores').doc('${ownerUid}_$keepMe');
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 150));
      if ((await keepDoc.get()).data()?['hiddenFromProfile'] == true) break;
    }
    expect((await keepDoc.get()).data()?['hiddenFromProfile'], isTrue,
        reason: 'eye tap persists the toggle');
    expect(find.text('Hidden'), findsNWidgets(2)); // optimistic UI caught up
    debugPrint('[hide_test] eye tap → keepMe hiddenFromProfile=true, both cards marked');

    // Restore for the viewer test below.
    await TrueFanProfileService.instance.setHidden(anilistId: keepMe, hidden: false);
  });

  testWidgets('viewer: hidden titles are filtered out everywhere, forgery denied',
      (tester) async {
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZHideViewer');

    // Service-level: the public fetch excludes the hidden anime.
    final visible = await TrueFanProfileService.instance.fetchVisibleEntriesFor(ownerUid);
    for (final e in visible) {
      debugPrint('[hide_test] viewer sees {anilistId: ${e.anilistId}, rank: ${e.rank}}');
    }
    expect(visible.map((e) => e.anilistId), [keepMe]);

    // A different user cannot touch someone else's toggle.
    final foreign = FirebaseFirestore.instance.collection('trueFanScores').doc('${ownerUid}_$hideMe');
    await expectLater(foreign.update({'hiddenFromProfile': false}), _denied);
    await expectLater(
      foreign.set({'hiddenFromProfile': false}, SetOptions(merge: true)),
      _denied,
    );
    debugPrint('[hide_test] foreign toggle writes denied');

    // Public profile UI: only the visible title, and no toggles for viewers.
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: UserProfileScreen(userId: ownerUid)),
    ));
    await pumpUntil(tester, find.text('🏆 True Fan'));
    await pumpUntil(tester, find.text('ZZ Keep Me'));
    expect(find.text('ZZ Hide Me'), findsNothing);
    expect(find.text('Hidden'), findsNothing);
    expect(find.byIcon(LucideIcons.eye), findsNothing);
    expect(find.byIcon(LucideIcons.eyeOff), findsNothing);
    debugPrint('[hide_test] viewer profile shows only visible titles, read-only');

    // The hidden score is still on the leaderboard for everyone.
    final board = await TrueFanScoreService.instance.topScores(hideMe);
    expect(board.map((e) => e.userId), contains(ownerUid));
  });
}
