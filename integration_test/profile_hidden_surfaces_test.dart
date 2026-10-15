import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/features/profile/wrapped_screen.dart';
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

/// The own profile follows kAniStatsEnabled and kWrappedEnabled: a Stats tab
/// and a Wrapped banner only while they are on, and a tab bar whose length
/// matches its tabs either way (a mismatch throws when the profile builds).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    await claimTestHandle('zzprof');
  });

  testWidgets('ui: the own profile shows Stats and Wrapped only while their flags are on', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile');

    // The header, where the Wrapped banner sat above Time Capsule.
    await pumpUntil(tester, find.text('Time Capsule'));
    expect(find.textContaining('Wrapped', skipOffstage: false), kWrappedEnabled ? findsWidgets : findsNothing);

    // The tab bar sits under a tall header: scroll down to it. Off-screen
    // tabs count too, so a Stats tab cannot hide past the edge.
    Finder tab(String label) =>
        find.ancestor(of: find.text(label, skipOffstage: false), matching: find.byType(Tab, skipOffstage: false));
    await tester.dragUntilVisible(find.text('Posts'), find.byType(NestedScrollView), const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tab('Fan Art'), findsOneWidget);
    expect(tab('Stats'), kAniStatsEnabled ? findsOneWidget : findsNothing);
    expect(tester.takeException(), isNull);
  });
}
