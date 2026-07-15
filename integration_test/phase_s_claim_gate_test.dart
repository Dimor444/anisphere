import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/features/profile/widgets/username_field.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';

/// Fix S verification, emulator suite ONLY — never production data.
///  - anifan_ placeholders and anisphere* handles are rules-denied AND
///    client-mirrored ("reserved" feedback, no failed transaction).
///  - suggestHandle never returns a reserved handle from either branch.
///  - THE regression that matters: fresh-account pre-fills stay claimable
///    ("Anime Fan" -> animefan claims end-to-end) or become EMPTY, never
///    born-reserved.
///  - The gate re-prompts on relaunch when not completed (no persistence).
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}

Future<String> signInEmail(String email) async {
  final auth = FirebaseAuth.instance;
  await AuthService.instance.signOut();
  try {
    await auth.createUserWithEmailAndPassword(email: email, password: 'zz-sr1-pass');
  } on FirebaseAuthException catch (e) {
    if (e.code != 'email-already-in-use') rethrow;
    await auth.signInWithEmailAndPassword(email: email, password: 'zz-sr1-pass');
  }
  return auth.currentUser!.uid;
}

String gatePrefill(WidgetTester tester) => tester
    .widget<TextField>(find.descendant(
        of: find.byType(UserNameField), matching: find.byType(TextField)))
    .controller!
    .text;

// Unique per run so re-runs against a warm emulator stay clean (a claimed
// handle would legitimately suppress the gate on the second pass).
final String run = (DateTime.now().millisecondsSinceEpoch % 1000000).toString();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('suggestHandle never emits a reserved handle', (tester) async {
    expect(FollowService.suggestHandle('Anime Fan', fallback: 'anifan_abc123'), 'animefan');
    expect(FollowService.suggestHandle('AniSphere Fan', fallback: 'anifan_abc123'), '',
        reason: 'primary branch hits the anisphere prefix -> empty');
    expect(FollowService.suggestHandle('Admin', fallback: 'anifan_abc123'), '',
        reason: 'primary branch hits the exact reserved set -> empty');
    expect(FollowService.suggestHandle('أوسمان عثمان', fallback: 'anifan_abc123'), '',
        reason: 'sanitizes empty, placeholder fallback filtered -> empty');
    expect(FollowService.suggestHandle('美咲', fallback: 'kazenoyuki'), 'kazenoyuki',
        reason: 'legacy non-placeholder fallback still suggested');
  });

  testWidgets('rules + mirror: placeholder and anisphere* are unclaimable', (tester) async {
    final db = FirebaseFirestore.instance;
    final denied = throwsA(isA<FirebaseException>()
        .having((e) => e.code, 'code', 'permission-denied'));

    // A holds an auto-generated placeholder (unregistered by design).
    final aUid = await signInEmail('zz.sr1.a$run@test.dev');
    await FollowService.instance.ensureProfile();
    final aHandle = (await FollowService.instance.getUser(aUid))!.userName;
    expect(FollowService.placeholderHandlePattern.hasMatch(aHandle), isTrue);

    // B: client mirror rejects instantly (no transaction attempted)…
    final bUid = await signInEmail('zz.sr1.b$run@test.dev');
    await FollowService.instance.ensureProfile();
    await expectLater(FollowService.instance.claimUserName(aHandle),
        throwsA(isA<UserNameTakenException>()));
    await expectLater(FollowService.instance.claimUserName('anisphere_support'),
        throwsA(isA<UserNameTakenException>()));
    expect(await FollowService.instance.isUserNameAvailable(aHandle), isFalse);
    expect(await FollowService.instance.isUserNameAvailable('anisphere_support'), isFalse);

    // …and the RULES deny it even when the client mirror is bypassed.
    await expectLater(db.collection('usernames').doc(aHandle).set({'uid': bUid}), denied);
    await expectLater(
        db.collection('usernames').doc('anisphere_support').set({'uid': bUid}), denied);
    debugPrint('[sr1] placeholder + anisphere* denied by rules AND mirrored client-side');

    // REGRESSION: a normal handle still claims end-to-end (transaction +
    // getAfter untouched under the new ruleset).
    await FollowService.instance.claimUserName('zzsr1b$run');
    final b = (await FollowService.instance.getUser(bUid))!;
    expect(b.userName, 'zzsr1b$run');
    expect((await db.collection('usernames').doc('zzsr1b$run').get()).data()?['uid'], bUid);
    debugPrint('[sr1] normal handle zzsr1b claimed end-to-end under new rules');
  });

  testWidgets('ui: "Anime Fan" pre-fill is claimable end-to-end, no Later button online',
      (tester) async {
    await signInEmail('zz.sr1.v$run@test.dev');
    // Same shape as the default 'Anime Fan' -> 'animefan' suggestion, made
    // unique per run so a warm emulator can't have claimed it already.
    await FollowService.instance.ensureProfile(displayName: 'Anime Fan $run');

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/feed');

    await pumpUntil(tester, find.text('Claim your username'));
    expect(gatePrefill(tester), 'animefan$run', reason: 'default pre-fill stays claimable');
    expect(find.text('Not now — you can claim later'), findsNothing,
        reason: 'Later never shows online');
    await binding.takeScreenshot('sr1_gate_prefill_animefan');

    await pumpUntil(tester, find.text('Available ✓'));
    expect(find.text('Not now — you can claim later'), findsNothing);
    await tester.tap(find.text('Claim'));
    await pumpUntilGone(tester, find.text('Claim your username'));
    final me = await FollowService.instance
        .getUser(AuthService.instance.uid!);
    expect(me!.userName, 'animefan$run');
    debugPrint('[sr1] animefan pre-fill claimed end-to-end, gate popped');
    await binding.takeScreenshot('sr1_gate_claimed_freed');
  });

  testWidgets('ui: "AniSphere Fan" pre-fills EMPTY; gate re-prompts on relaunch',
      (tester) async {
    await signInEmail('zz.sr1.w$run@test.dev');
    await FollowService.instance.ensureProfile(displayName: 'AniSphere Fan');

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/feed');
    await pumpUntil(tester, find.text('Claim your username'));
    expect(gatePrefill(tester), '',
        reason: 'anisphere-prefixed suggestion must be filtered to empty');
    await binding.takeScreenshot('sr1_gate_prefill_empty_anisphere_name');

    // Not completed -> a fresh launch prompts again (no persistence).
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/feed');
    await pumpUntil(tester, find.text('Claim your username'));
    expect(gatePrefill(tester), '');
    debugPrint('[sr1] empty pre-fill for AniSphere Fan; gate re-prompted on relaunch');
  });
}
