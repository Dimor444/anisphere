import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/community_vote_service.dart';

import 'support/session.dart';

const _base = 'http://127.0.0.1:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
const _ownerHeaders = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

const _frieren = 154587;
// No anime has this id, so AniList leaves it out of the answer — the path an
// id filtered as adult takes too.
const _ghost = 999999999;
const _plantedCover = 'https://example.com/planted.jpg';

/// A tally written past the rules, carrying a title and cover no build would
/// send — what a voter could have written before the format checks.
Future<void> _seedTally(String day, int anime, String title, String cover, int votes) async {
  final res = await http.patch(
    Uri.parse('$_base/community_votes/$day/tally/$anime'),
    headers: _ownerHeaders,
    body: jsonEncode({
      'fields': {
        'anilist_id': {'integerValue': '$anime'},
        'animeTitle': {'stringValue': title},
        'animeCover': {'stringValue': cover},
        'dayId': {'stringValue': day},
        'voteCount': {'integerValue': '$votes'},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed tally failed: ${res.body}');
}

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// The vote board and its history show each anime as AniList has it, by the
/// tally's anilist_id — never the title and cover written into the tally — and
/// an id AniList leaves out as "Title unavailable", keeping its row.
///
/// Firestore is the emulator; the titles come from AniList itself, so this
/// needs the network.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    await claimTestHandle('zzvoteboard');
  });

  testWidgets("ui: the vote board shows AniList's titles, never a tally's own", (tester) async {
    final now = DateTime.now();
    final today = CommunityVoteService.dayIdFor(now);
    final yesterday = CommunityVoteService.dayIdFor(now.toUtc().subtract(const Duration(days: 1)));
    await _seedTally(today, _frieren, 'ZZ planted title', _plantedCover, 3);
    await _seedTally(today, _ghost, 'ZZ planted ghost', _plantedCover, 1);
    await _seedTally(yesterday, _frieren, 'ZZ planted yesterday', _plantedCover, 2);

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    appRouter.go('/community-vote');
    await pumpUntil(tester, find.textContaining('Frieren'));
    await pumpUntil(tester, find.text('Title unavailable'));
    expect(find.textContaining('ZZ planted'), findsNothing);
    final covers = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).map((c) => c.imageUrl);
    expect(covers, isNot(contains(_plantedCover)));
    expect(covers.where((u) => u.contains('/file/anilistcdn/media/anime/cover/')), isNotEmpty);
    expect(tester.takeException(), isNull);

    appRouter.go('/community-vote/history');
    await pumpUntil(tester, find.textContaining('Frieren'));
    expect(find.textContaining('ZZ planted'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
