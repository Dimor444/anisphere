import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/data/models/news.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/feed_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/news_service.dart';

const _newsTitleSeason = 'ZZNews: Frieren Season 2 announced';
const _newsTitleMovie = 'ZZNews: Chainsaw Man movie premiere';
const _popPostLow = 'ZZPop post with no likes';
const _popPostHot = 'ZZPop post everyone liked';

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

/// Seed one news doc through the emulator's REST API with the special
/// `Bearer owner` admin credential — the collection is create-locked for
/// clients (rules), exactly like production, so the SDK can't seed it.
Future<void> _seedNews({
  required String id, // fixed doc id → re-running overwrites, never duplicates
  required String title,
  required String category,
  required DateTime publishedAt,
  String description = '',
  int animeId = 0,
  String animeTitle = '',
  String sourceUrl = '',
}) async {
  final res = await http.patch(
    Uri.parse('http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents/news/$id'),
    headers: {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'fields': {
        'title': {'stringValue': title},
        'description': {'stringValue': description},
        'category': {'stringValue': category},
        'source': {'stringValue': 'AniSphere'},
        'publishedAt': {'timestampValue': publishedAt.toUtc().toIso8601String()},
        'views': {'integerValue': '0'},
        'saves': {'integerValue': '0'},
        if (sourceUrl.isNotEmpty) 'sourceUrl': {'stringValue': sourceUrl},
        if (animeId > 0)
          'animeIds': {
            'arrayValue': {
              'values': [
                {'integerValue': '$animeId'}
              ]
            }
          },
        if (animeTitle.isNotEmpty)
          'animeTitles': {
            'arrayValue': {
              'values': [
                {'stringValue': animeTitle}
              ]
            }
          },
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'news seed failed: ${res.body}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

    final now = DateTime.now();
    await _seedNews(
      id: 'zz-test-season',
      title: _newsTitleSeason,
      category: 'Season',
      publishedAt: now.subtract(const Duration(hours: 3)),
      description: 'The continuation nobody stopped hoping for is official.',
      animeId: 154587,
      animeTitle: 'Frieren',
      sourceUrl: 'https://example.com/frieren-s2',
    );
    await _seedNews(
      id: 'zz-test-movie',
      title: _newsTitleMovie,
      category: 'Movie',
      publishedAt: now.subtract(const Duration(hours: 1)),
      description: 'Reze arc hits theaters worldwide.',
    );
  });

  testWidgets('service: news stream, category filter, save + view tallies', (tester) async {
    final svc = NewsService.instance;
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();

    // Newest first, both seeded articles present.
    final all = await svc.getNewsArticles().first;
    final idxMovie = all.indexWhere((a) => a.title == _newsTitleMovie);
    final idxSeason = all.indexWhere((a) => a.title == _newsTitleSeason);
    expect(idxMovie, isNot(-1));
    expect(idxSeason, isNot(-1));
    expect(idxMovie, lessThan(idxSeason), reason: 'newer article should rank first');

    final seasonArticle = all[idxSeason];
    expect(seasonArticle.category, NewsCategory.season);
    expect(seasonArticle.animeIds, [154587]);
    expect(seasonArticle.animeTitleAt(0), 'Frieren');

    // Category filter (composite-indexed query).
    final seasonOnly = await svc.getNewsArticles(category: NewsCategory.season).first;
    expect(seasonOnly.any((a) => a.title == _newsTitleSeason), isTrue);
    expect(seasonOnly.any((a) => a.title == _newsTitleMovie), isFalse);

    // Search.
    final found = await svc.searchNews('frieren season').first;
    expect(found.any((a) => a.title == _newsTitleSeason), isTrue);

    // Views bump (fire-and-forget → allow it to land).
    svc.incrementViews(seasonArticle.id);
    await Future.delayed(const Duration(seconds: 1));
    var refreshed = (await svc.getNewsArticles(category: NewsCategory.season).first)
        .firstWhere((a) => a.id == seasonArticle.id);
    expect(refreshed.views, 1);

    // Save round trip with tally.
    expect(await svc.watchIsSaved(seasonArticle.id).first, isFalse);
    await svc.saveArticle(seasonArticle.id);
    expect(await svc.watchIsSaved(seasonArticle.id).first, isTrue);
    refreshed = (await svc.getNewsArticles(category: NewsCategory.season).first)
        .firstWhere((a) => a.id == seasonArticle.id);
    expect(refreshed.saves, 1);
    await svc.unsaveArticle(seasonArticle.id);
    expect(await svc.watchIsSaved(seasonArticle.id).first, isFalse);

    await svc.reportNews(seasonArticle.id, 'other');
  });

  testWidgets('service: popular posts rank by likes for follow-less users', (tester) async {
    final feed = FeedService.instance;
    final follow = FollowService.instance;

    // User A publishes two posts and likes the second.
    await AuthService.instance.signOut();
    final aUid = (await AuthService.instance.initAuth()).uid;
    await follow.ensureProfile(userName: 'ZZPopA');
    await feed.createPost(content: _popPostLow, userName: 'ZZPopA');
    final hotId = await feed.createPost(content: _popPostHot, userName: 'ZZPopA');
    await feed.likePost(hotId, aUid);

    // User B follows nobody → popular fallback, most-liked first.
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await follow.ensureProfile(userName: 'ZZPopB');
    expect(await follow.hasAnyFollowing(), isFalse);
    expect(await feed.isUserFollowingAnyone('ignored'), isFalse);

    final popular = await feed.getPopularPosts().first;
    final idxHot = popular.indexWhere((p) => p.content == _popPostHot);
    final idxLow = popular.indexWhere((p) => p.content == _popPostLow);
    expect(idxHot, isNot(-1));
    expect(idxLow, isNot(-1));
    expect(idxHot, lessThan(idxLow), reason: 'likes DESC');

    // After following A, the normal feed carries A's posts.
    await follow.followUser(aUid);
    final feedB = await feed.getFeedPosts().first;
    expect(feedB.any((p) => p.content == _popPostHot), isTrue);
    await follow.unfollowUser(aUid);
  });

  testWidgets('ui: popular fallback renders, then switches on first follow; news tab + detail', (tester) async {
    // Signed in as B (follows nobody after the unfollow above).
    final follow = FollowService.instance;
    final aUid = (await follow.searchUsers('zzpopa')).first.id;

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/feed');

    // Popular fallback: nudge banner + section header + ranked posts.
    await pumpUntil(tester, find.textContaining('Popular This Week'));
    await pumpUntil(tester, find.text(_popPostHot));

    // First follow lands → feed switches to following-only in real time.
    await follow.followUser(aUid);
    await pumpUntilGone(tester, find.textContaining('Popular This Week'));
    await pumpUntil(tester, find.text(_popPostHot));
    await follow.unfollowUser(aUid);

    // News: list renders seeded article, detail shows the full description.
    appRouter.push('/news');
    await pumpUntil(tester, find.text(_newsTitleMovie));
    await tester.tap(find.text(_newsTitleMovie));
    await pumpUntil(tester, find.text('Reze arc hits theaters worldwide.'));
  });
}
