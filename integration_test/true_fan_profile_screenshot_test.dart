// One-off screenshot capture for the profile "🏆 True Fan" section — run with
// flutter drive so the driver saves PNGs (see test_driver/integration_test.dart).
// Uses REAL AniList ids so covers resolve when the network allows.
//
// Captures:
//  1. OWNER profile — Death Note hidden (dimmed + "Hidden" pill), eye toggles
//     on every card, count chip showing the TRUE TOTAL (3) incl. the hidden one.
//  2. VIEWER public profile — the same user seen by someone else: Death Note
//     filtered out, no toggles.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/core/theme/app_theme.dart';
import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/features/profile/user_profile_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/true_fan_profile_service.dart';
import 'package:anisphere/services/true_fan_score_service.dart';

const _base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
const _ownerHeaders = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

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

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Real AniList ids so covers/titles resolve in the screenshot.
  const aot = 16498; //   Attack on Titan — 0 faster seeds → #1
  const deathNote = 1535; // Death Note   — 2 faster seeds → #3 (gets hidden)
  const mha = 21459; //   My Hero Academia — 11 faster    → #12

  late String ownerUid;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('capture: owner profile — hidden card marked, chip shows true total', (tester) async {
    await AuthService.instance.signOut();
    ownerUid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZShot');

    for (var t = 1; t <= 2; t++) {
      await _seedScore('zzdn$t', deathNote, t.toDouble());
    }
    for (var t = 1; t <= 11; t++) {
      await _seedScore('zzmha$t', mha, t.toDouble());
    }
    final svc = TrueFanScoreService.instance;
    expect(await svc.submitPass(anilistId: aot, animeTitle: 'Attack on Titan', score: 9, timeSeconds: 21.4), isTrue);
    expect(await svc.submitPass(anilistId: deathNote, animeTitle: 'Death Note', score: 8, timeSeconds: 33.1), isTrue);
    expect(await svc.submitPass(anilistId: mha, animeTitle: 'My Hero Academia', score: 7, timeSeconds: 48.9), isTrue);

    // The owner hides Death Note from their public profile.
    await TrueFanProfileService.instance.setHidden(anilistId: deathNote, hidden: true);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: ProfileScreen())),
    ));
    // Let ranks, AniList metadata and cover images settle.
    await pumpFor(tester, const Duration(seconds: 12));

    // Bring the section into view before capturing.
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -260));
    await pumpFor(tester, const Duration(seconds: 3));

    await binding.takeScreenshot('true_fan_owner_hidden_card');
  });

  testWidgets('capture: viewer public profile — hidden title filtered out', (tester) async {
    // A different signed-in user opens the owner's public profile.
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZViewer');

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: UserProfileScreen(userId: ownerUid)),
    ));
    await pumpFor(tester, const Duration(seconds: 12));

    await binding.takeScreenshot('true_fan_viewer_filtered');
  });
}
