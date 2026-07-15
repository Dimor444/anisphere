import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/chart_service.dart';
import 'package:anisphere/services/trending_service.dart';

/// Chart service talks to the LIVE AniList GraphQL API (read-only, a handful
/// of rate-limited queries). Firebase still points at the emulators so
/// pumping the app can't touch production data.
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
  });

  testWidgets('service: 100 entries, three genuinely different lists, instant cache', (tester) async {
    final svc = ChartService.instance;

    final allTime = await svc.getTopAnime(ChartFilter.allTime);
    expect(allTime.length, ChartService.topCount, reason: 'all-time must be a full Top 100');
    expect(allTime.first.rank, 1);
    expect(allTime.last.rank, ChartService.topCount);
    // Sorted by score (ties allowed).
    for (var i = 1; i < allTime.length; i++) {
      expect(allTime[i].score, lessThanOrEqualTo(allTime[i - 1].score));
    }
    expect(allTime.first.score, greaterThan(8.5), reason: 'top of all-time should score high');
    expect(allTime.first.ratings, greaterThan(0));
    expect(allTime.first.coverImage, startsWith('http'));

    final year = await svc.getTopAnime(ChartFilter.year);
    expect(year.length, ChartService.topCount);

    // Season can legitimately be shorter than 100, but must not be empty.
    final season = await svc.getTopAnime(ChartFilter.season);
    expect(season, isNotEmpty);

    // The three slices are genuinely different lists.
    Set<int> ids(List<AnimeChartEntry> l) => l.map((e) => e.anilistId).toSet();
    expect(ids(allTime), isNot(equals(ids(year))));
    expect(ids(allTime), isNot(equals(ids(season))));
    expect(ids(season), isNot(equals(ids(year))));
    // Sanity: the season's top show is good enough to chart within the year.
    expect(ids(season).intersection(ids(year)), isNotEmpty);

    // Cache: second read within TTL returns the same instance, instantly.
    final sw = Stopwatch()..start();
    final again = await svc.getTopAnime(ChartFilter.allTime);
    sw.stop();
    expect(identical(again, allTime), isTrue);
    expect(sw.elapsedMilliseconds, lessThan(50));
  });

  testWidgets('service: fetchById resolves chart entries, even deep in the list', (tester) async {
    final chart = await ChartService.instance.getTopAnime(ChartFilter.allTime);

    // Rank 95 — a pagination-fetched entry that is certainly not trending.
    final deep = chart[94];
    final full = await TrendingService.instance.fetchById(deep.anilistId);
    expect(full, isNotNull, reason: 'every chart id must resolve');
    expect(full!.id, deep.anilistId);
    expect(full.title, deep.title, reason: 'both sides prefer english ?? romaji');
    expect(full.description, isNotEmpty, reason: 'detail fetch fills the synopsis');

    // Unknown id → clean null (the "not found" state), not an exception.
    expect(await TrendingService.instance.fetchById(999999999), isNull);
  });

  testWidgets('ui: chart tab renders rows and switches filters', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/discover');

    await pumpUntil(tester, find.text('📊 Chart'));
    // The tab bar is scrollable — Chart starts off-screen; bring it in first.
    await tester.ensureVisible(find.text('📊 Chart'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('📊 Chart'));
    await pumpUntil(tester, find.text('AniSphere Top 100'));
    // Cached from the service test → rows paint without a new fetch.
    await pumpUntil(tester, find.textContaining('ratings'));

    await tester.tap(find.text('Season'));
    await pumpUntil(tester, find.textContaining('ratings'));

    await tester.tap(find.text('Year'));
    await pumpUntil(tester, find.textContaining('ratings'));

    // Tap the top row → detail screen loads the full record by id:
    // synopsis + Add to List prove it resolved beyond the partial extra.
    await tester.tap(find.textContaining('ratings').first);
    await pumpUntil(tester, find.text('Synopsis'));
    await pumpUntil(tester, find.text('Add to List'));
  });
}
