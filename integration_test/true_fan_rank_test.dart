import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/true_fan_score_service.dart';

import 'support/session.dart';

/// Owner-credential seed of another player's passed run — bypasses rules.
Future<void> _seedScore(String userId, int anilistId, double timeSeconds) async {
  final res = await http.patch(
    Uri.parse('http://127.0.0.1:8080/v1/projects/anisphere-36cb0/databases/(default)/documents'
        '/trueFanScores/${userId}_$anilistId'),
    headers: const {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
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
        'countryCode': {'stringValue': 'JP'},
        'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed score failed: ${res.body}');
}

/// The rank the True Fan result card prints, against the emulator only.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final svc = TrueFanScoreService.instance;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    await claimTestHandle('zzrank');
  });

  testWidgets("a run's rank counts faster players, never the player's own best", (tester) async {
    // Its own anime per run: the player's best written here stays on the
    // emulator under this run's uid, and would be another player to the next.
    final anime = 991000 + DateTime.now().millisecondsSinceEpoch % 100000;
    await _seedScore('zzrank_a', anime, 30);
    await _seedScore('zzrank_b', anime, 40);
    await _seedScore('zzrank_c', anime, 60);

    // Nothing of their own on the board yet: two players are faster than 45s.
    expect(await svc.rankOfRun(anime, 45), 3);

    // Their 45s pass lands on the board. The run itself is not counted
    // against itself (a stored time equal to it is not faster)…
    expect(await svc.submitPass(anilistId: anime, animeTitle: 'ZZ', score: 8, timeSeconds: 45), isTrue);
    expect(await svc.rankOfRun(anime, 45), 3);
    // …and a slower run later has the same two players ahead of it. The
    // board's own count includes the player's 45s best, which is why the
    // card does not use it directly.
    expect(await svc.rankForTime(anime, 50), 4);
    expect(await svc.rankOfRun(anime, 50), 3);

    // Faster than everyone: first.
    expect(await svc.rankOfRun(anime, 20), 1);
  });
}
