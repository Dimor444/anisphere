import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/chart_service.dart';
import 'package:anisphere/shared/widgets/anime_card.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Discover says only what is true: Search's empty state is recent searches
/// and AniList's trending list, not fixed "trending searches" and sample
/// "top results"; the chart labels AniList's popularity as list counts, not
/// ratings; and unscored rows sit under their own heading, unnumbered.
///
/// The chart and the trending list come from AniList itself, so this needs
/// the network. The unscored check follows whatever the season holds.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    await claimTestHandle('zzdiscover');
  });

  testWidgets('ui: Search and the chart say only what is true', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    appRouter.go('/discover');
    // The tab bar scrolls and Search is its last tab, off the edge until
    // scrolled to — a tap there lands on nothing and leaves another tab up.
    final searchTab = find.widgetWithText(Tab, 'Search');
    await pumpUntil(tester, searchTab);
    await tester.ensureVisible(searchTab);
    await pumpUntil(tester, searchTab.hitTestable());
    await tester.tap(searchTab);
    // The empty state's own heading over AniList's trending list — inside
    // its list, which the "Trending" tab label is not.
    await pumpUntil(tester, find.descendant(of: find.byType(ListView), matching: find.text('Trending')));
    expect(find.text('Trending searches'), findsNothing);
    expect(find.text('Top results'), findsNothing);
    expect(find.byType(AnimeCard), findsNothing, reason: 'the sample grid is gone');
    expect(tester.takeException(), isNull);

    final chartTab = find.widgetWithText(Tab, 'Chart');
    await tester.ensureVisible(chartTab);
    await pumpUntil(tester, chartTab.hitTestable());
    await tester.tap(chartTab);
    // The Season chip in the chart's own header.
    final seasonChip = find.descendant(
        of: find.ancestor(of: find.text('AniSphere Top 100'), matching: find.byType(Row)).first,
        matching: find.text('Season'));
    // Hit-testable, not just present: the chart slides in from the next tab,
    // and a tap before it arrives lands on nothing.
    await pumpUntil(tester, seasonChip.hitTestable());
    await tester.tap(seasonChip);
    await pumpUntil(tester, find.textContaining(' on lists'));
    expect(find.textContaining(' ratings'), findsNothing);

    final season = await ChartService.instance.getTopAnime(ChartFilter.season);
    // The list on screen is the season's, not All Time's.
    await pumpUntil(tester, find.text(season.first.title));
    final unscored = season.where((e) => e.score == null).length;
    debugPrint('Season chart: ${season.length - unscored} scored, $unscored unscored.');
    expect(season.skipWhile((e) => e.score != null).every((e) => e.score == null), isTrue,
        reason: 'every scored row comes before every unscored one');
    final heading = find.text('Not scored yet');
    // The chart's own list: the one Scrollable under the column that holds
    // its fixed header. Other tabs' lists can still be in the tree.
    final chartList = find
        .descendant(
            of: find.ancestor(of: find.text('AniSphere Top 100'), matching: find.byType(Column)).first,
            matching: find.byType(Scrollable))
        .first;
    if (unscored > 0) {
      await tester.scrollUntilVisible(heading, 400, scrollable: chartList);
      expect(heading, findsOneWidget);
    } else {
      expect(heading, findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
