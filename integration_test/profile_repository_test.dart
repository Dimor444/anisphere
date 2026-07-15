import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/my_list_service.dart';
import 'package:anisphere/services/profile_repository.dart';

/// "March 2024"-style month-year, as the join-date chip renders it.
final _monthYear = RegExp(r'^[A-Z][a-z]+ \d{4}$');

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Each signOut + initAuth mints a fresh anonymous uid, so assertions for a
/// user must finish before switching identities.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('repository: live header data for the signed-in user', (tester) async {
    final repo = ProfileRepository.instance;
    final follow = FollowService.instance;
    final myList = MyListService.instance;

    // ── User A: profile with header fields + two list entries
    await AuthService.instance.signOut();
    final aUid = (await AuthService.instance.initAuth()).uid;
    await follow.ensureProfile(
      userName: 'ZZProfileA',
      displayName: 'Zeta Zed',
      bio: 'ZZ header bio',
    );
    await myList.addToMyList(1, 'Cowboy Bebop', '', ListStatus.completed);
    await myList.addToMyList(20, 'Naruto', '', ListStatus.current);

    final profileA = (await repo.watchProfile().first)!;
    expect(profileA.displayName, 'Zeta Zed');
    expect(profileA.bio, 'ZZ header bio');
    expect(profileA.isVerified, isFalse, reason: 'clients can never grant verification');
    expect(profileA.avatarUrl, isNull, reason: 'empty userAvatar maps to null');
    expect(profileA.initials, 'ZZ', reason: 'first letters of up to two words');
    expect(repo.joinDate(profileA), matches(_monthYear));

    // Restart-style ensureProfile (no args, as MainShell calls it) is
    // create-only: the existing identity must not be clobbered.
    await follow.ensureProfile();
    final profileA2 = (await repo.watchProfile().first)!;
    expect(profileA2.displayName, 'Zeta Zed');
    expect(profileA2.bio, 'ZZ header bio');

    final countsA = await repo.fetchCounts();
    expect(countsA.anime, 2);
    expect(countsA.followers, 0);
    expect(countsA.following, 0);

    // ── User B: minimal profile, follows A
    await AuthService.instance.signOut();
    final bUid = (await AuthService.instance.initAuth()).uid;
    expect(bUid, isNot(aUid));
    await follow.ensureProfile(userName: 'ZZProfileB');
    await follow.followUser(aUid);

    final profileB = (await repo.watchProfile().first)!;
    expect(profileB.displayName, 'Anime Fan', reason: 'neutral default display name');
    expect(profileB.bio, isEmpty);
    expect(profileB.isVerified, isFalse);
    expect(profileB.initials, 'AF');

    final countsB = await repo.fetchCounts();
    expect(countsB.anime, 0);
    expect(countsB.followers, 0);
    expect(countsB.following, 1);

    // Missing profile doc → auth-metadata join date, same display format.
    expect(repo.joinDate(null), matches(_monthYear));
  });

  testWidgets('header renders live Firestore values, never the mock ones', (tester) async {
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(
      userName: 'ZZHeaderUser',
      displayName: 'Kaze No',
      bio: 'ZZ live bio',
    );
    await MyListService.instance.addToMyList(5, 'Cowboy Bebop', '', ListStatus.completed);

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    await pumpUntil(tester, find.text('Kaze No'));
    expect(find.text('ZZ live bio'), findsOneWidget);
    await pumpUntil(tester, find.text('1')); // anime count aggregation
    expect(find.text('0'), findsNWidgets(2), reason: 'followers + following');
    expect(find.text('✓ Verified'), findsNothing, reason: 'not verified');
    expect(find.textContaining('📅'), findsOneWidget, reason: 'join-date chip');

    // The sample user's header values must never appear on the own profile.
    expect(find.text('KazeNoYuki'), findsNothing);
    expect(find.text('347'), findsNothing);
    expect(find.text('2.3K'), findsNothing);
  });

  testWidgets('fresh user: neutral header, never verified, no mock identity', (tester) async {
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    // Exactly what MainShell runs on startup.
    await FollowService.instance.ensureProfile();

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    await pumpUntil(tester, find.text('Anime Fan'));
    expect(find.text('✓ Verified'), findsNothing, reason: 'clients can never self-verify');
    expect(find.text('0'), findsNWidgets(3), reason: 'anime + followers + following');
    expect(find.textContaining('📅'), findsOneWidget, reason: 'join-date chip from createdAt');
    expect(find.text('KazeNoYuki'), findsNothing);
    expect(find.text('Yuki'), findsNothing);
  });

  testWidgets('edit profile: sheet saves name + bio, header updates live', (tester) async {
    await AuthService.instance.signOut();
    final uid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(
      userName: 'ZZEditUser',
      displayName: 'Before Edit',
      bio: 'old bio',
    );

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));
    await pumpUntil(tester, find.text('Before Edit'));

    await tester.tap(find.text('Edit Profile'));
    await pumpUntil(tester, find.text('Save'));
    expect(find.text('old bio'), findsWidgets, reason: 'sheet prefills current bio');

    await tester.enterText(find.byType(TextField).at(0), 'After Edit');
    await tester.enterText(find.byType(TextField).at(1), 'fresh bio');
    await tester.tap(find.text('Save'));

    // Header reflects the write through the live users/{uid} stream — no
    // manual refresh anywhere.
    await pumpUntil(tester, find.text('After Edit'));
    await pumpUntil(tester, find.text('fresh bio'));

    // Restart-style ensureProfile (create-only) must keep the edits, and the
    // doc must remain unverified.
    await FollowService.instance.ensureProfile();
    final profile = (await ProfileRepository.instance.watchProfile().first)!;
    expect(profile.displayName, 'After Edit');
    expect(profile.bio, 'fresh bio');
    expect(profile.isVerified, isFalse);

    // Sensitive fields stay client-immutable: self-verification is denied.
    await expectLater(
      FirebaseFirestore.instance.collection('users').doc(uid).update({'isVerified': true}),
      throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')),
    );
  });
}
