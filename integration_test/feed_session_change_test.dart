// The home feed must survive the signed-in identity changing underneath it.
//
// Regression for "Bad state: Stream has already been listened to" at
// feed_screen.dart's ValueListenableBuilder. SessionLifecycle tears the
// following watch down on an identity change (followingIdsListenable → null)
// and re-attaches it for the new uid (→ the new list). The feed's StreamBuilder
// was handed a null stream in between, cancelling its subscription, and then
// the SAME single-subscription popular stream again — a new guest follows
// nobody, so popular mode survived the change and nothing minted a fresh one.
//
// Drives the real transition rather than poking the listenable: a guest, the
// real SessionLifecycle installed as main() does, a real sign-out and a real
// Continue as Guest, with the feed mounted throughout. In the app this was
// seen when a dead guest was replaced at launch with the feed already built;
// signing out from Settings does not reach it, because that navigates away
// and the feed is rebuilt from scratch.
//
// Emulator suite only (auth + firestore):
//   flutter test integration_test/feed_session_change_test.dart -d <simulator>
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/core/session_lifecycle.dart';
import 'package:anisphere/core/theme/app_theme.dart';
import 'package:anisphere/features/feed/feed_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';

/// Pumps frames for [duration] of real time, so Firestore snapshots and the
/// lifecycle's queued teardown/attach actually land between frames.
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('feed survives sign-out + Continue as Guest while mounted', (tester) async {
    final first = await AuthService.instance.signInAsGuest();

    final container = ProviderContainer();
    SessionLifecycle.instance.install(container);
    addTearDown(() async {
      await SessionLifecycle.instance.debugDispose();
      container.dispose();
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: const Scaffold(body: FeedScreen())),
    ));

    // The following watch lands ([] — a new guest follows nobody), so the feed
    // is in popular mode with its stream subscribed.
    await pumpFor(tester, const Duration(seconds: 4));
    expect(FollowService.instance.followingIdsListenable.value, isNotNull,
        reason: 'the first session\'s following watch never attached');

    // The identity changes under the mounted feed. Frames keep rendering
    // between the two halves — in the app the gap is the new guest being
    // minted — so the feed really builds with the torn-down (null) watch.
    // Without this pump both changes coalesce into one frame, the builder
    // never sees null, and the test passes on the broken code.
    await AuthService.instance.signOut();
    await pumpFor(tester, const Duration(seconds: 2));
    expect(FollowService.instance.followingIdsListenable.value, isNull,
        reason: 'sign-out should have torn the following watch down');
    final second = await AuthService.instance.signInAsGuest();
    expect(second.uid, isNot(first.uid));

    await pumpFor(tester, const Duration(seconds: 6));
    expect(FollowService.instance.followingIdsListenable.value, isNotNull,
        reason: 'the new session\'s following watch never attached');
    expect(tester.takeException(), isNull);
  });
}
