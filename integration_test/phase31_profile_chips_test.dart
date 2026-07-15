import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/feed_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/streak_service.dart';

/// Phase 3.1 verification, emulator suite ONLY — never production data.
///  - Posts stat derives from a count() over the tab's query shape: a
///    drifted users/{uid}.postsCount (2 docs, counter 1 — replicating the
///    @dimor444 production state) must display 2.
///  - Visitors see join-date + streak chips; a broken/stale streak shows NO
///    chip; null createdAt renders '—'; own profile rail unchanged.
///  - postsEpoch invalidation: creating a post refreshes the mounted header.
const _postA = 'ZZ31 first post';
const _postB = 'ZZ31 second post';

Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<String> signInEmail(String email) async {
  final auth = FirebaseAuth.instance;
  await AuthService.instance.signOut();
  try {
    await auth.createUserWithEmailAndPassword(email: email, password: 'zz-phase31-pass');
  } on FirebaseAuthException catch (e) {
    if (e.code != 'email-already-in-use') rethrow;
    await auth.signInWithEmailAndPassword(email: email, password: 'zz-phase31-pass');
  }
  return auth.currentUser!.uid;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String vUid; // viewer driving the UI
  late String pUid; // poster with drifted counter (2 docs, counter 1)
  late String sUid; // stale streak (old lastActiveDay, nonzero stored streak)
  late String nUid; // profile doc without createdAt

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('seed: drifted poster, stale streak, null createdAt', (tester) async {
    final db = FirebaseFirestore.instance;

    // ── P: 2 real posts, then a client-legal -1 on the counter (rules admit
    // ±1 bumps) to replicate the under-counted production state exactly.
    pUid = await signInEmail('zz.phase31.p@test.dev');
    await FollowService.instance.ensureProfile();
    await FollowService.instance.claimUserName('zzphase31p');
    await StreakService.instance.checkIn(); // live 1-day streak for the positive case
    if ((await db.collection('posts').where('userId', isEqualTo: pUid).count().get()).count ==
        0) {
      await FeedService.instance.createPost(content: _postA);
      await FeedService.instance.createPost(content: _postB);
      await db.collection('users').doc(pUid).update({'postsCount': FieldValue.increment(-1)});
    }
    final docCount =
        (await db.collection('posts').where('userId', isEqualTo: pUid).count().get()).count;
    final counter = (await db.collection('users').doc(pUid).get()).data()!['postsCount'];
    debugPrint('[phase31] P drift replicated: post docs=$docCount, postsCount field=$counter');
    expect(docCount, 2);
    expect(counter, 1);

    // ── S: stored streak 7 but lastActiveDay long past. Arbitrary streak
    // fields are rules-blocked for clients, so use the EMULATOR's owner
    // bypass (never possible against production).
    sUid = await signInEmail('zz.phase31.s@test.dev');
    await FollowService.instance.ensureProfile();
    final res = await http.patch(
      Uri.parse('http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/'
          'documents/users/$sUid'
          '?updateMask.fieldPaths=currentStreak&updateMask.fieldPaths=lastActiveDay'),
      headers: {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
      body: '{"fields":{"currentStreak":{"integerValue":"7"},'
          '"lastActiveDay":{"stringValue":"2026-07-01"}}}',
    );
    expect(res.statusCode, 200, reason: 'emulator owner patch failed: ${res.body}');
    debugPrint('[phase31] S seeded: currentStreak=7, lastActiveDay=2026-07-01 (stale)');

    // ── N: legal create WITHOUT createdAt (the create rule doesn't require
    // it) — identityProvider then yields createdAt == null.
    nUid = await signInEmail('zz.phase31.n@test.dev');
    final nHandle = 'anifan_${nUid.substring(0, 6).toLowerCase()}';
    if (!(await db.collection('users').doc(nUid).get()).exists) {
      await db.collection('users').doc(nUid).set({
        'userId': nUid,
        'userName': nHandle,
        'userNameLower': nHandle,
        'displayName': 'No Join Date',
        'userAvatar': '',
        'bio': '',
        'isVerified': false,
        'isPlus': false,
        'countryCode': 'XX',
        'followerCount': 0,
        'followingCount': 0,
        'postsCount': 0,
        'isPrivate': false,
        'currentStreak': 0,
        'longestStreak': 0,
        'lastActiveDay': '',
      });
    }
    debugPrint('[phase31] N seeded without createdAt');

    // ── V drives the UI; claimed handle keeps the shell's claim gate away.
    vUid = await signInEmail('zz.phase31.v@test.dev');
    await FollowService.instance.ensureProfile();
    await FollowService.instance.claimUserName('zzphase31v');
    debugPrint('[phase31] seeded V=$vUid P=$pUid S=$sUid N=$nUid');
  });

  testWidgets('ui: derived posts count, visitor chips, own rail unchanged', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    // ── P: header Posts == 2 (derived) over a tab listing both posts,
    // despite the stored counter saying 1. Live streak chip shows.
    appRouter.go('/profile/$pUid');
    await pumpUntil(tester, find.text('@zzphase31p'));
    await pumpUntil(tester, find.text(_postA));
    await pumpUntil(tester, find.text(_postB));
    await pumpUntil(tester, find.text('2')); // the derived Posts stat
    await pumpUntil(tester, find.text('🔥 1-day streak'));
    await pumpUntil(tester, find.textContaining('📅 '));
    debugPrint('[phase31] visiting P: header Posts=2, tab lists 2, counter field=1');
    await settle(tester);
    await binding.takeScreenshot('phase31_visiting_posts_2of2');

    // ── S: join chip yes, NO streak chip (stored 7 is stale — display
    // derives 0 from lastActiveDay and hides the chip entirely).
    appRouter.go('/profile/$sUid');
    await pumpUntil(tester, find.textContaining('📅 '));
    await settle(tester);
    expect(find.textContaining('day streak'), findsNothing,
        reason: 'stale streak must not render as live');
    expect(find.textContaining('Start your streak'), findsNothing,
        reason: 'owner-directed nudge never shows to visitors');
    debugPrint('[phase31] visiting S: join chip only, stale 7-streak hidden');
    await binding.takeScreenshot('phase31_visiting_stale_streak');

    // ── N: null createdAt renders the em-dash, no crash.
    appRouter.go('/profile/$nUid');
    await pumpUntil(tester, find.text('No Join Date'));
    await pumpUntil(tester, find.text('📅 —'));
    debugPrint('[phase31] visiting N: join date renders — for null createdAt');
    await settle(tester);
    await binding.takeScreenshot('phase31_visiting_null_createdat');

    // ── Own profile: full rail unchanged (nudge copy, True Fan chip), and
    // the postsEpoch invalidation refreshes the mounted header live.
    appRouter.go('/profile');
    await pumpUntil(tester, find.text('@zzphase31v'));
    await pumpUntil(tester, find.textContaining('🏆'));
    await settle(tester);
    expect(find.text('0'), findsWidgets); // Posts 0 before the live create
    await binding.takeScreenshot('phase31_own_unchanged');

    await FeedService.instance.createPost(content: 'ZZ31 live invalidation post');
    await pumpUntil(tester, find.text('1')); // Posts recounts with no renav
    debugPrint('[phase31] postsEpoch invalidation: own Posts 0 -> 1 live');
    await binding.takeScreenshot('phase31_own_after_live_post');
  });
}
