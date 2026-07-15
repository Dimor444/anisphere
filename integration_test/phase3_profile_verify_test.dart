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
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/shared/widgets/follow_button.dart';
import 'package:anisphere/shared/widgets/gradient_button.dart';
import 'package:anisphere/shared/widgets/user_avatar.dart';

/// Phase 3 verification: unified Instagram-style profile header.
///  - banner + avatar + action row in one bounded Stack: no crop, no gap,
///    no overflow, no dead tap zones (bottom-edge taps register)
///  - same layout own vs visiting; counts identical for the same uid
///  - long displayName + empty bio doesn't overflow
/// Emulator suite only — never production data. Email accounts (not anon)
/// so the target user can sign back in for the own-profile comparison.
///
/// Geometry mirrored from profile_screen.dart:
const double kActionRowHeight = 40; // the fixed action-row box
const double kAvatarSize = 88; // UserAvatar diameter (radius 44; +3 ring outside)

const String kLongName = 'Extraordinarily Long Display Name Overflow Check';

Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// The follow button's own label (the stats row also says "Following").
Finder followButtonLabel(String text) =>
    find.descendant(of: find.byType(FollowButton), matching: find.text(text));

/// The header avatar, selected by geometry: the shell keeps other branches
/// (feed rail, closed drawer) in the tree with off-screen avatars, so tree
/// order is unreliable. The header's is the only ON-SCREEN 88px avatar.
Finder headerAvatar(WidgetTester tester) {
  final all = find.byType(UserAvatar);
  final n = all.evaluate().length;
  for (var i = 0; i < n; i++) {
    final r = tester.getRect(all.at(i));
    debugPrint('[phase3] avatar candidate #$i: $r');
    if (r.left >= 0 && r.width == 88.0) return all.at(i);
  }
  fail('no on-screen 88px header avatar among $n candidates');
}

Future<String> signInEmail(String email) async {
  final auth = FirebaseAuth.instance;
  await AuthService.instance.signOut();
  try {
    await auth.createUserWithEmailAndPassword(email: email, password: 'zz-phase3-pass');
  } on FirebaseAuthException catch (e) {
    if (e.code != 'email-already-in-use') rethrow;
    await auth.signInWithEmailAndPassword(email: email, password: 'zz-phase3-pass');
  }
  return auth.currentUser!.uid;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String aUid; // target: long displayName, empty bio
  late String bUid; // viewer: follows A

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('seed: A (long name, no bio) and B (follows A)', (tester) async {
    aUid = await signInEmail('zz.phase3.a@test.dev');
    await FollowService.instance.ensureProfile();
    await FollowService.instance.updateProfile(displayName: kLongName, bio: '');
    // Claim handles so MainShell's @username gate (a branch-level modal that
    // sits over the profile tab and eats its taps) never prompts.
    await FollowService.instance.claimUserName('zzphase3a');

    bUid = await signInEmail('zz.phase3.b@test.dev');
    await FollowService.instance.ensureProfile();
    await FollowService.instance.claimUserName('zzphase3b');
    await FollowService.instance.followUser(aUid);
    expect(await FollowService.instance.isFollowing(aUid), isTrue);
    debugPrint('[phase3] seeded A=$aUid (long name, no bio), B=$bUid follows A');
  });

  testWidgets('visiting profile (as B): layout, geometry, taps, no overflow', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile/$aUid');

    // Long displayName renders (ellipsized; an overflow would fail the test).
    await pumpUntil(tester, find.text(kLongName));
    await pumpUntil(tester, find.byType(FollowButton));

    // ── Geometry: avatar fully visible, name column clear of it.
    final avatar = tester.getRect(headerAvatar(tester));
    debugPrint('[phase3] visiting avatar rect: $avatar');
    expect(avatar.width, kAvatarSize);
    expect(avatar.left, 19, reason: 'left 16 + 3 ring');
    final nameTop = tester.getRect(find.text(kLongName)).top;
    expect(nameTop, greaterThan(avatar.bottom),
        reason: 'name column must start below the avatar (breathing room)');

    // ── Action row: measure natural sizes; must fit the fixed 40px box.
    final followRect = tester.getRect(find.byType(FollowButton));
    final messageRect = tester.getRect(find.widgetWithText(GestureDetector, 'Message').first);
    debugPrint('[phase3] MEASURED FollowButton height: ${followRect.height}');
    debugPrint('[phase3] MEASURED Message button height: ${messageRect.height}');
    expect(followRect.height, lessThanOrEqualTo(kActionRowHeight));
    expect(messageRect.height, lessThanOrEqualTo(kActionRowHeight));

    // B already follows A.
    await pumpUntil(tester, followButtonLabel('Following'));

    // ── Counts as the visitor sees them: exactly one follower.
    await pumpUntil(tester, find.text('Followers'));
    expect(find.text('1'), findsWidgets, reason: 'A has exactly one follower');
    await binding.takeScreenshot('phase3_visiting_longname_nobio');

    // ── Bottom-edge tap on the FollowButton — the dead-zone regression check.
    final bottomEdge = Offset(followRect.center.dx, followRect.bottom - 1);
    await tester.tapAt(bottomEdge);
    await pumpUntil(tester, followButtonLabel('Follow'));
    debugPrint('[phase3] bottom-edge tap registered (Following -> Follow)');
    // Restore the follow for the own-profile comparison below.
    await tester.tapAt(bottomEdge);
    await pumpUntil(tester, followButtonLabel('Following'));

    // ── Scroll past the header and back — no clip/overflow at any offset.
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('phase3_visiting_scrolled');
    await tester.drag(find.byType(NestedScrollView), const Offset(0, 500));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('own profile (as A): same layout, same counts, edit sheet from bottom-edge tap',
      (tester) async {
    await signInEmail('zz.phase3.a@test.dev');

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile');

    await pumpUntil(tester, find.text(kLongName));
    await pumpUntil(tester, find.byType(GradientButton));
    // The router still carries the previous test's /profile/:uid page — let
    // its exit transition finish so geometry is measured at rest.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // ── Geometry: same avatar size and alignment as the visiting profile.
    final avatar = tester.getRect(headerAvatar(tester));
    debugPrint('[phase3] own avatar rect: $avatar');
    expect(avatar.width, kAvatarSize);
    expect(avatar.left, 19, reason: 'left-aligned, identical to visiting');

    // ── Measure the Edit Profile button (the taller action-row candidate).
    // Label-scoped: other shell branches can hold their own GradientButtons.
    final editFinder = find.widgetWithText(GradientButton, 'Edit Profile');
    await pumpUntil(tester, editFinder);
    final editRect = tester.getRect(editFinder.first);
    debugPrint('[phase3] Edit Profile rect: $editRect (height ${editRect.height})');
    expect(editRect.height, lessThanOrEqualTo(kActionRowHeight),
        reason: 'adjust _actionRowHeight if this ever fails');

    // ── Counts: A sees the SAME numbers B saw (1 follower).
    await pumpUntil(tester, find.text('Followers'));
    expect(find.text('1'), findsWidgets, reason: 'own header shows the same 1 follower');
    await binding.takeScreenshot('phase3_own_rest');

    // ── Center tap first (sanity), then the bottom-edge dead-zone check.
    await tester.tapAt(editRect.center);
    await pumpUntil(tester, find.text('Display Name'));
    debugPrint('[phase3] center tap opened the full edit sheet');
    await tester.tapAt(const Offset(20, 100)); // barrier tap dismisses the sheet
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Display Name'), findsNothing, reason: 'sheet dismissed');

    await tester.tapAt(Offset(editRect.center.dx, editRect.bottom - 1));
    await pumpUntil(tester, find.text('Display Name'));
    debugPrint('[phase3] bottom-edge tap opened the full edit sheet (no dead zone)');
    await binding.takeScreenshot('phase3_own_edit_sheet');
    await tester.tapAt(const Offset(20, 100)); // barrier tap dismisses the sheet
    await tester.pump(const Duration(milliseconds: 600));

    // ── Scroll past the header and back.
    await tester.drag(find.byType(NestedScrollView).first, const Offset(0, -500), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('phase3_own_scrolled');
    await tester.drag(find.byType(NestedScrollView).first, const Offset(0, 500), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('phase3_own_rest_after_scroll');
  });
}
