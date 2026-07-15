import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/community_vote_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/streak_service.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

String dayAgo(int days) =>
    CommunityVoteService.dayIdFor(DateTime.now().toUtc().subtract(Duration(days: days)));

final _denied = throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'));

Future<Map<String, dynamic>> streakFields(String uid, String label) async {
  final d = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data() ??
      const <String, dynamic>{};
  final f = {
    'currentStreak': d['currentStreak'],
    'longestStreak': d['longestStreak'],
    'lastActiveDay': d['lastActiveDay'],
  };
  debugPrint('[streak_test] $label — users/$uid: $f');
  return f;
}

/// Rules-bypassing seed via the emulator's admin credential — stages
/// yesterday/gap states that clients can't (and must not) write themselves.
Future<void> adminSeedStreak(String uid,
    {required int current, required int longest, required String lastDay}) async {
  final res = await http.patch(
    Uri.parse('http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents/users/$uid'
        '?updateMask.fieldPaths=currentStreak&updateMask.fieldPaths=longestStreak&updateMask.fieldPaths=lastActiveDay'),
    headers: {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'fields': {
        'currentStreak': {'integerValue': '$current'},
        'longestStreak': {'integerValue': '$longest'},
        'lastActiveDay': {'stringValue': lastDay},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'admin seed failed: ${res.body}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('streak lifecycle: first, same-day, consecutive, gap, forgery', (tester) async {
    final svc = StreakService.instance;
    final today = CommunityVoteService.dayIdFor(DateTime.now());

    await AuthService.instance.signOut();
    final uid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZStreak');
    final doc = FirebaseFirestore.instance.collection('users').doc(uid);

    // 1. First launch ever → 1 / 1 / today.
    await streakFields(uid, 'case 1 before');
    svc.resetSession();
    expect(await svc.checkIn(), isTrue, reason: 'first check-in writes');
    var f = await streakFields(uid, 'case 1 after');
    expect(f['currentStreak'], 1);
    expect(f['longestStreak'], 1);
    expect(f['lastActiveDay'], today);

    // 2. Re-open the same UTC day → NO write, values unchanged.
    svc.resetSession(); // fresh app session, same day
    expect(await svc.checkIn(), isFalse, reason: 'same day: nothing to write');
    f = await streakFields(uid, 'case 2 after');
    expect(f['currentStreak'], 1);
    expect(f['longestStreak'], 1);
    expect(f['lastActiveDay'], today);

    // 3. lastActiveDay == yesterday → +1 (and longest follows).
    await adminSeedStreak(uid, current: 3, longest: 3, lastDay: dayAgo(1));
    await streakFields(uid, 'case 3 before');
    svc.resetSession();
    expect(await svc.checkIn(), isTrue);
    f = await streakFields(uid, 'case 3 after');
    expect(f['currentStreak'], 4, reason: 'consecutive day increments by one');
    expect(f['longestStreak'], 4);
    expect(f['lastActiveDay'], today);

    // 4. Gap (older than yesterday) → reset to 1, longest preserved.
    await adminSeedStreak(uid, current: 4, longest: 9, lastDay: dayAgo(3));
    await streakFields(uid, 'case 4 before');
    svc.resetSession();
    expect(await svc.checkIn(), isTrue);
    f = await streakFields(uid, 'case 4 after');
    expect(f['currentStreak'], 1, reason: 'gap resets the streak');
    expect(f['longestStreak'], 9, reason: 'longest streak is preserved');
    expect(f['lastActiveDay'], today);

    // 5. Forgery: jumping the streak is denied by rules.
    await expectLater(doc.update({'currentStreak': 9999}), _denied);
    await expectLater(
      doc.update({'currentStreak': 9999, 'longestStreak': 9999, 'lastActiveDay': today}),
      _denied,
    );
    await streakFields(uid, 'case 5 after (unchanged)');

    // 6. A streak write that also touches sensitive fields is denied.
    await expectLater(
      doc.update({'currentStreak': 2, 'longestStreak': 9, 'lastActiveDay': today, 'isVerified': true}),
      _denied,
    );
    await expectLater(
      doc.update({'currentStreak': 2, 'longestStreak': 9, 'lastActiveDay': today, 'isPlus': true}),
      _denied,
    );
    f = await streakFields(uid, 'case 6 after (unchanged)');
    expect(f['currentStreak'], 1);
    expect(f['longestStreak'], 9);
  });

  testWidgets('chip: start nudge, then live streak — never the mock 42', (tester) async {
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZStreakChip');

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    // Before the first check-in: the nudge, and never the sample 42.
    await pumpUntil(tester, find.text('🔥 Start your streak'));
    expect(find.text('🔥 42-day streak'), findsNothing);

    // Check in while the profile is open — the streamed doc updates the chip
    // live, singular form and all.
    StreakService.instance.resetSession(); // singleton memo may hold today from the previous test
    expect(await StreakService.instance.checkIn(), isTrue);
    await pumpUntil(tester, find.text('🔥 1-day streak'));
    expect(find.text('🔥 42-day streak'), findsNothing);
  });

  testWidgets('chip: lapsed streak DISPLAYS as 0 with no write', (tester) async {
    await AuthService.instance.signOut();
    final uid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZStreakLapsed');
    // Stored streak 5, but last check-in was 3 days ago (no check-in runs in
    // this test — ProfileScreen is read-only).
    await adminSeedStreak(uid, current: 5, longest: 8, lastDay: dayAgo(3));
    await streakFields(uid, 'lapsed before display');

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ProfileScreen())),
    ));

    // Read-side: the lapsed streak shows the start nudge, never the stale 5.
    await pumpUntil(tester, find.text('🔥 Start your streak'));
    expect(find.text('🔥 5-day streak'), findsNothing);

    // The stored value is untouched — the next real check-in handles reset.
    final f = await streakFields(uid, 'lapsed after display');
    expect(f['currentStreak'], 5);
    expect(f['longestStreak'], 8);
    expect(f['lastActiveDay'], dayAgo(3));
  });
}
