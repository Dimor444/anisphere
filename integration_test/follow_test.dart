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
import 'package:anisphere/services/feed_service.dart';
import 'package:anisphere/services/follow_service.dart';

const _postA = 'ZZFollow post from A #zzfollow';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> pumpUntilGone(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}

/// Two distinct anonymous users: each signOut + initAuth mints a fresh uid.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String aUid;
  late String bUid;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('service: two-user follow lifecycle with counters and feed filter', (tester) async {
    final follow = FollowService.instance;
    final feed = FeedService.instance;

    // ── User A: profile + one post
    await AuthService.instance.signOut();
    aUid = (await AuthService.instance.initAuth()).uid;
    await follow.ensureProfile(userName: 'ZZUserA', bio: 'ZZ bio for A');
    await feed.createPost(content: _postA, userName: 'ZZUserA', isVerified: true);
    var profileA = (await follow.watchUser(aUid).first)!;
    expect(profileA.postsCount, 1);
    expect(profileA.userName, 'ZZUserA');

    // ── User B: fresh identity
    await AuthService.instance.signOut();
    bUid = (await AuthService.instance.initAuth()).uid;
    expect(bUid, isNot(aUid));
    await follow.ensureProfile(userName: 'ZZUserB');

    // B doesn't follow A yet: A appears in suggestions and search.
    var suggestions = await follow.getFollowSuggestions(limit: 10).first;
    expect(suggestions.any((u) => u.id == aUid), isTrue);
    expect(suggestions.any((u) => u.id == bUid), isFalse, reason: 'self is excluded');
    final found = await follow.searchUsers('zzusera');
    expect(found.any((u) => u.id == aUid), isTrue);

    // B's feed is empty — B follows nobody and has no posts.
    var feedB = await feed.getFeedPosts().first;
    expect(feedB.where((p) => p.content == _postA), isEmpty);

    // ── Follow: symmetric docs + both counters
    await follow.followUser(aUid);
    expect(await follow.isFollowing(aUid), isTrue);
    profileA = (await follow.watchUser(aUid).first)!;
    var profileB = (await follow.watchUser(bUid).first)!;
    expect(profileA.followerCount, 1);
    expect(profileB.followingCount, 1);

    final followersOfA = await follow.getUserFollowers(aUid).first;
    expect(followersOfA.map((u) => u.id), contains(bUid));
    final followingOfB = await follow.getUserFollowing(bUid).first;
    expect(followingOfB.map((u) => u.id), contains(aUid));

    // Feed now carries A's post; suggestions no longer offer A.
    feedB = await feed.getFeedPosts().first;
    expect(feedB.any((p) => p.content == _postA), isTrue);
    suggestions = await follow.getFollowSuggestions(limit: 10).first;
    expect(suggestions.any((u) => u.id == aUid), isFalse);

    // ── Unfollow: everything reverts
    await follow.unfollowUser(aUid);
    expect(await follow.isFollowing(aUid), isFalse);
    profileA = (await follow.watchUser(aUid).first)!;
    profileB = (await follow.watchUser(bUid).first)!;
    expect(profileA.followerCount, 0);
    expect(profileB.followingCount, 0);
    feedB = await feed.getFeedPosts().first;
    expect(feedB.where((p) => p.content == _postA), isEmpty);
  });

  testWidgets('ui: profile header, stats, follow button toggle', (tester) async {
    // Still signed in as B from the previous test.
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile/$aUid');

    // Header renders A's live profile.
    await pumpUntil(tester, find.text('ZZUserA'));
    await pumpUntil(tester, find.text('ZZ bio for A'));

    // Outline "Follow" → tap → gradient "Following" (confirmed by Firestore).
    // Two buttons can match (header + A's post card below); both flip, so
    // tapping the header one and waiting for ALL "Follow" labels to clear is
    // exactly the real-time propagation we want to prove.
    await pumpUntil(tester, find.text('Follow'));
    await tester.tap(find.text('Follow').first);
    await pumpUntilGone(tester, find.text('Follow'));
    expect(await FollowService.instance.isFollowing(aUid), isTrue);

    // Followers screen lists B in real time.
    appRouter.push('/profile/$aUid/followers');
    await pumpUntil(tester, find.text('ZZUserB'));

    // Cleanup: revert the follow.
    await FollowService.instance.unfollowUser(aUid);
  });
}
