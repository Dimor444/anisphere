import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/features/challenges/challenges_screen.dart';
import 'package:anisphere/firebase_options.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Challenges shows League and Events only while their flags are on, with a
/// tab count that matches its bar, and no game card promises gold that
/// nothing pays.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    await claimTestHandle('zzchal');
  });

  testWidgets('ui: Challenges has the real tabs only, and no unpaid prizes', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/challenges');
    await pumpUntil(tester, find.widgetWithText(Tab, 'Games'));

    final labels = tester.widgetList<Tab>(find.byType(Tab, skipOffstage: false)).map((t) => t.text).toList();
    expect(labels, [
      'Games',
      'True Fan',
      if (kChallengeLeagueEnabled) 'League',
      if (kChallengeEventsEnabled) 'Events',
    ]);

    await pumpUntil(tester, find.text('▶ Play'));
    expect(find.textContaining('🟡', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
