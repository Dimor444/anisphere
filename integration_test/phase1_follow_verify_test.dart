import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/shared/widgets/follow_button.dart';

/// Phase 1 verification: follow/unfollow reflects live in lists and in both
/// profile headers (relationship-derived counts), and an immediate re-follow
/// is an error-free no-op. Emulator suite only — never production data.
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<int> subCount(String uid, String sub) async {
  final agg = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection(sub)
      .count()
      .get();
  return agg.count ?? 0;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String aUid;
  late String aHandle;
  late String bUid;
  late String bHandle;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('service: idempotent follow lifecycle with live counts', (tester) async {
    final follow = FollowService.instance;

    // ── User A: fresh anonymous identity + rules-legal generated handle
    await AuthService.instance.signOut();
    aUid = (await AuthService.instance.initAuth()).uid;
    await follow.ensureProfile();
    aHandle = (await follow.getUser(aUid))!.userName;
    expect(aHandle, startsWith('anifan_'));

    // ── User B
    await AuthService.instance.signOut();
    bUid = (await AuthService.instance.initAuth()).uid;
    expect(bUid, isNot(aUid));
    await follow.ensureProfile();
    bHandle = (await follow.getUser(bUid))!.userName;

    // ── Follow: symmetric relationship docs + aggregation counts
    var epochBefore = follow.followGraphEpoch.value;
    await follow.followUser(aUid);
    expect(await follow.isFollowing(aUid), isTrue);
    expect(follow.followGraphEpoch.value, epochBefore + 1);
    expect((await follow.getUserFollowers(aUid).first).map((u) => u.id), contains(bUid));
    expect((await follow.getUserFollowing(bUid).first).map((u) => u.id), contains(aUid));
    expect(await subCount(aUid, 'followers'), 1);
    expect(await subCount(bUid, 'following'), 1);

    // ── Immediate re-follow: no permission error, no double-count, no epoch bump
    epochBefore = follow.followGraphEpoch.value;
    await follow.followUser(aUid); // must not throw
    expect(follow.followGraphEpoch.value, epochBefore, reason: 're-follow is a no-op');
    expect(await subCount(aUid, 'followers'), 1);
    expect(await subCount(bUid, 'following'), 1);
    final aDoc = (await follow.getUser(aUid))!;
    expect(aDoc.followerCount, 1, reason: 'counter field must not double-bump');

    // ── Unfollow reverses; second unfollow is a no-op
    await follow.unfollowUser(aUid);
    expect(await follow.isFollowing(aUid), isFalse);
    expect(await subCount(aUid, 'followers'), 0);
    expect(await subCount(bUid, 'following'), 0);
    epochBefore = follow.followGraphEpoch.value;
    await follow.unfollowUser(aUid); // must not throw
    expect(follow.followGraphEpoch.value, epochBefore);
    expect((await follow.getUser(aUid))!.followerCount, 0);
  });

  testWidgets('ui: both headers and lists reflect follow/unfollow live', (tester) async {
    // Still signed in as B from the previous test.
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    // Own profile tab first, so its header is mounted BEFORE the follow —
    // proving it updates live (no restart, no re-navigation refetch).
    appRouter.go('/profile');
    await pumpUntil(tester, find.text('@$bHandle'));
    await pumpUntil(tester, find.text('Following')); // stats label row
    await binding.takeScreenshot('phase1_own_before_follow');

    // Visit A's profile: header renders 0 followers from the aggregation.
    appRouter.push('/profile/$aUid');
    await pumpUntil(tester, find.text('@$aHandle'));
    await pumpUntil(tester, find.text('Follow'));
    await binding.takeScreenshot('phase1_visiting_before_follow');

    // Tap Follow → button flips and the visiting header re-counts to 1
    // with no navigation and no restart.
    await tester.tap(find.text('Follow').first);
    await pumpUntil(tester, find.text('Following').first);
    await pumpUntil(tester, find.text('1'));
    expect(await FollowService.instance.isFollowing(aUid), isTrue);
    await binding.takeScreenshot('phase1_visiting_after_follow');

    // A's Followers list shows B live (UserTile subtitles the @handle).
    appRouter.push('/profile/$aUid/followers');
    await pumpUntil(tester, find.textContaining(bHandle));
    await binding.takeScreenshot('phase1_followers_list');
    appRouter.pop();
    await tester.pump(const Duration(milliseconds: 400));

    // Back on the own tab: the already-mounted header now shows Following 1.
    appRouter.go('/profile');
    await pumpUntil(tester, find.text('@$bHandle'));
    await pumpUntil(tester, find.text('1'));
    await binding.takeScreenshot('phase1_own_after_follow');

    // Unfollow from A's profile: reverses live in the header. Target the
    // button's label specifically — the stats row also says "Following".
    appRouter.push('/profile/$aUid');
    await pumpUntil(tester, find.text('@$aHandle'));
    final followingBtn = find.descendant(
        of: find.byType(FollowButton), matching: find.text('Following'));
    await pumpUntil(tester, followingBtn);
    await tester.tap(followingBtn.first);
    final followBtn = find.descendant(
        of: find.byType(FollowButton), matching: find.text('Follow'));
    await pumpUntil(tester, followBtn);
    expect(await FollowService.instance.isFollowing(aUid), isFalse);
    await binding.takeScreenshot('phase1_visiting_after_unfollow');
  });
}
