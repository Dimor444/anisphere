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
import 'package:anisphere/services/my_list_service.dart';

// High ids that will never collide with real AniList entries.
const _idA = 900000001; // seeded as CURRENT, score 8
const _idB = 900000002; // seeded as PLANNING, unrated
const _titleA = 'ZZTest Current Anime';
const _titleB = 'ZZTest Planned Anime';
const _cover = 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/default.jpg';

/// Pump frames until [finder] matches (the app has perpetual animations, so
/// pumpAndSettle would never return).
Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Pump frames until [finder] stops matching — e.g. the previous tab view
/// detaching once the tab-switch animation completes.
Future<void> pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}

Future<void> _cleanup() async {
  final svc = MyListService.instance;
  try {
    await svc.removeFromMyList(_idA);
    await svc.removeFromMyList(_idB);
  } catch (_) {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Run against the local emulator suite — anonymous auth is disabled in the
    // production console, and tests should never write production data anyway.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await _cleanup();
  });

  testWidgets('service: add / read / update / remove against live Firestore', (tester) async {
    final svc = MyListService.instance;

    // add
    await svc.addToMyList(_idA, _titleA, _cover, ListStatus.current);
    expect(await svc.isAnimeInMyList(_idA), isTrue);

    // stream contains it
    final list = await svc.getMyList().first;
    final entry = list.firstWhere((e) => e.anilistId == _idA);
    expect(entry.title, _titleA);
    expect(entry.status, ListStatus.current);
    expect(entry.episodesWatched, 0);
    expect(entry.score, isNull);

    // field updates
    await svc.updateAnimeStatus(_idA, ListStatus.completed);
    await svc.updateEpisodesWatched(_idA, 12);
    await svc.updateScore(_idA, 8);
    await svc.updateNotes(_idA, 'integration test note');
    final updated = (await svc.watchEntry(_idA).first)!;
    expect(updated.status, ListStatus.completed);
    expect(updated.episodesWatched, 12);
    expect(updated.score, 8);
    expect(updated.notes, 'integration test note');

    // batched editor save
    await svc.updateEntry(_idA, status: ListStatus.current, episodesWatched: 5, score: 8, notes: 'n2');
    final batched = (await svc.watchEntry(_idA).first)!;
    expect(batched.status, ListStatus.current);
    expect(batched.episodesWatched, 5);

    // remove
    await svc.removeFromMyList(_idA);
    expect(await svc.isAnimeInMyList(_idA), isFalse);
  });

  testWidgets('ui: tabs, real-time updates, quick actions', (tester) async {
    final svc = MyListService.instance;
    await svc.addToMyList(_idA, _titleA, _cover, ListStatus.current);
    await svc.updateScore(_idA, 8);
    await svc.addToMyList(_idB, _titleB, _cover, ListStatus.planning);

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/my-list');

    // All tab: both entries + stats card visible.
    await pumpUntil(tester, find.text(_titleA));
    await pumpUntil(tester, find.text(_titleB));
    expect(find.text('Total'), findsOneWidget);

    Finder tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

    // Watching tab: only the CURRENT entry (wait out the slide transition —
    // the outgoing All view stays attached until the animation completes).
    await tester.tap(tab('Watching'));
    await pumpUntilGone(tester, find.text(_titleB));
    expect(find.text(_titleA), findsWidgets);

    // Completed tab: empty state.
    await tester.tap(tab('Completed'));
    await pumpUntil(tester, find.text('Add anime to get started'));
    await pumpUntilGone(tester, find.text(_titleA));

    // Real-time: mark A completed from the service — it must appear in the
    // Completed tab without any UI interaction.
    await svc.updateAnimeStatus(_idA, ListStatus.completed);
    await pumpUntil(tester, find.text(_titleA));

    // Quick actions: long-press → remove from list.
    await tester.longPress(find.text(_titleA).first);
    await pumpUntil(tester, find.text('Remove from List'));
    await tester.tap(find.text('Remove from List'));
    // Entry disappears in real time; tab shows the empty state again once the
    // sheet's dismiss animation finishes.
    await pumpUntil(tester, find.text('Add anime to get started'));
    await pumpUntilGone(tester, find.text(_titleA));

    await _cleanup();
  });
}
