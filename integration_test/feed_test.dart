import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/feed_service.dart';
import 'package:anisphere/services/follow_service.dart';

// 'ZZTest' marker keeps seeded content identifiable for cleanup.
const _postContent = 'ZZTest feed post about #zztesttag greatness';
const _spoilerContent = 'ZZTest spoiler: the mentor dies';
const _commentContent = 'ZZTest first comment';

/// Pump frames until [finder] matches (the app has perpetual animations, so
/// pumpAndSettle would never return).
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

Future<void> _cleanup() async {
  try {
    final uid = (await AuthService.instance.initAuth()).uid;
    final posts = await FeedService.instance.getUserPosts(uid).first;
    for (final p in posts.where((p) => p.content.startsWith('ZZTest'))) {
      await FeedService.instance.deletePost(p.id);
    }
  } catch (_) {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Run against the local emulator suite — anonymous auth is disabled in the
    // production console, and tests should never write production data anyway.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    // Post batches bump postsCount on the author's profile doc — it must exist.
    // Two identities: a helper (followed, posts nothing) and the tester. The
    // follow pins the feed to following mode, so the UI test sees the
    // tester's seeded posts newest-first instead of the popular-ranked
    // fallback (whose ordering depends on leftover emulator data).
    await AuthService.instance.signOut();
    final helperUid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(userName: 'ZZFeedHelper');
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZTester');
    if (!await FollowService.instance.isFollowing(helperUid)) {
      await FollowService.instance.followUser(helperUid);
    }
    await _cleanup();
  });

  tearDownAll(_cleanup);

  testWidgets('service: create / like / comment / report / follow / delete', (tester) async {
    final svc = FeedService.instance;
    final uid = (await AuthService.instance.initAuth()).uid;

    // create — hashtags extracted, counters start at zero
    final postId = await svc.createPost(
      content: _postContent,
      userName: 'ZZTester',
      isVerified: true,
      anilistId: 154587,
      animeTitle: 'Frieren',
      isSpoiler: false,
    );
    var post = (await svc.watchPost(postId).first)!;
    expect(post.content, _postContent);
    expect(post.hashtags, ['zztesttag']);
    expect(post.likes, 0);
    expect(post.commentsCount, 0);
    expect(post.anilistId, 154587);

    // it lands on the first feed page (newest first)
    final feed = await svc.getFeedPosts().first;
    expect(feed.any((p) => p.id == postId), isTrue);

    // hashtag query + trending tally
    final tagged = await svc.getHashtagPosts('zztesttag').first;
    expect(tagged.any((p) => p.id == postId), isTrue);
    final trending = await FirebaseFirestore.instance.collection('trending_hashtags').doc('zztesttag').get();
    expect((trending.data()?['count'] as num).toInt(), greaterThanOrEqualTo(1));

    // like / unlike round trip with counter
    await svc.likePost(postId, uid);
    expect(await svc.isPostLikedByUser(postId, uid), isTrue);
    post = (await svc.watchPost(postId).first)!;
    expect(post.likes, 1);
    await svc.unlikePost(postId, uid);
    expect(await svc.isPostLikedByUser(postId, uid), isFalse);
    post = (await svc.watchPost(postId).first)!;
    expect(post.likes, 0);

    // comment / delete comment with counter
    final commentId = await svc.addComment(postId, _commentContent, userName: 'ZZTester');
    var comments = await svc.getComments(postId).first;
    expect(comments.any((c) => c.id == commentId && c.content == _commentContent), isTrue);
    post = (await svc.watchPost(postId).first)!;
    expect(post.commentsCount, 1);
    await svc.deleteComment(postId, commentId);
    comments = await svc.getComments(postId).first;
    expect(comments, isEmpty);

    // report is accepted (write-only collection)
    await svc.reportPost(postId, 'spam');

    // delete
    await svc.deletePost(postId);
    expect(await svc.watchPost(postId).first, isNull);
  });

  testWidgets('ui: feed renders posts, like, spoiler reveal, comments', (tester) async {
    final svc = FeedService.instance;
    final spoilerId = await svc.createPost(content: _spoilerContent, userName: 'ZZTester', isSpoiler: true);
    final postId = await svc.createPost(content: _postContent, userName: 'ZZTester');
    expect(spoilerId, isNotEmpty);

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/feed');

    // Both posts stream in; the spoiler one is blurred behind the reveal chip.
    await pumpUntil(tester, find.textContaining('ZZTest feed post'));
    await pumpUntil(tester, find.text('Spoiler — tap to reveal'));

    // Spoiler reveal.
    await tester.tap(find.text('Spoiler — tap to reveal'));
    await pumpUntilGone(tester, find.text('Spoiler — tap to reveal'));

    // Optimistic like: heart fills immediately.
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);

    // Open detail via the post body, send a comment, see it live.
    await tester.tap(find.textContaining('ZZTest feed post'));
    await pumpUntil(tester, find.byIcon(LucideIcons.send));
    await tester.enterText(find.byType(TextField).first, _commentContent);
    await tester.tap(find.byIcon(LucideIcons.send));
    await pumpUntil(tester, find.text(_commentContent));

    // Comment counter reached Firestore.
    final post = (await svc.watchPost(postId).first)!;
    expect(post.commentsCount, 1);
  });
}
