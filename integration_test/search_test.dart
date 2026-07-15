import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/trending_service.dart';

/// Search hits the LIVE AniList API (read-only, rate-limited). Firebase
/// points at the emulators so pumping the app can't touch production.
const _nonsense = 'zzqxvwkjy anime that cannot exist 4242';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    // Start from clean search history — previous runs leave entries behind.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history_v1');
    await prefs.remove('search_history_v2');
  });

  testWidgets('service: searchAnime finds real matches, empty for nonsense, cached', (tester) async {
    final svc = TrendingService.instance;

    final hits = await svc.searchAnime('dr. stone');
    expect(hits, isNotEmpty);
    expect(
      hits.any((a) => a.title.toLowerCase().contains('dr. stone')),
      isTrue,
      reason: 'query must actually filter — "dr. stone" should surface Dr. STONE',
    );
    final drStone = hits.firstWhere((a) => a.title.toLowerCase().contains('dr. stone'));
    expect(drStone.id, greaterThan(0));
    expect(drStone.coverUrl, startsWith('http'));
    expect(drStone.description, isNotEmpty, reason: 'search results carry full detail data');

    expect(await svc.searchAnime(_nonsense), isEmpty);

    // Session cache: identical instance on repeat.
    expect(identical(await svc.searchAnime('dr. stone'), hits), isTrue);
  });

  testWidgets('ui: typing searches, result opens detail, clear restores default; '
      'history saves only completed searches', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/discover');

    final field = find.byKey(const ValueKey('discover-search'));
    await pumpUntil(tester, field);

    // Type letter by letter (like a real user) → live results appear, but
    // NO keystroke fragment may enter history.
    const target = 'dr. stone';
    for (var i = 1; i <= target.length; i++) {
      await tester.enterText(field, target.substring(0, i));
      await tester.pump(const Duration(milliseconds: 120));
    }
    await pumpUntil(tester, find.textContaining('Dr. STONE'));

    // Static sample titles must NOT be shown as "results" anymore.
    expect(find.text('Naruto'), findsNothing);

    // Abandon without completing: clear → NO Recent searches section at all.
    await tester.tap(find.descendant(of: field, matching: find.byType(IconButton)));
    await pumpUntil(tester, find.text('Trending searches'));
    expect(find.text('Recent searches'), findsNothing,
        reason: 'live typing alone must never write history');

    // Search again and COMPLETE it by tapping a result.
    await tester.enterText(field, target);
    await pumpUntil(tester, find.textContaining('Dr. STONE'));
    await tester.tap(find.textContaining('Dr. STONE').first);
    await pumpUntil(tester, find.text('Synopsis'));
    await pumpUntil(tester, find.text('Add to List'));
    appRouter.pop();
    await tester.pump(const Duration(milliseconds: 400));

    // Nonsense → honest empty state (and no history entry — never completed).
    await tester.enterText(field, _nonsense);
    await pumpUntil(tester, find.textContaining('No anime found for'));

    // Clear → default view: exactly ONE history chip, the completed search.
    await tester.tap(find.descendant(of: field, matching: find.byType(IconButton)));
    await pumpUntil(tester, find.text('Recent searches'));
    expect(find.text(target), findsOneWidget);
    for (var i = 2; i < target.length; i++) {
      expect(find.text(target.substring(0, i)), findsNothing,
          reason: 'fragment "${target.substring(0, i)}" must not be in history');
    }
    expect(find.textContaining('zzqxvwkjy'), findsNothing);
    expect(find.text('Naruto'), findsOneWidget); // sample grid is back
  });
}
