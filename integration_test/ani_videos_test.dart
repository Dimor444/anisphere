import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/data/models/ani_video.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/ani_video_service.dart';
import 'package:anisphere/services/auth_service.dart';

import 'support/session.dart';

// 'ZZTest' marker keeps seeded content identifiable for cleanup.
const _caption = 'ZZTest video caption #zzvideotag';
const _spoilerCaption = 'ZZTest spoiler video — the mentor dies';
const _commentContent = 'ZZTest video comment';
const _malformedCaption = 'ZZTest malformed video';
// Stable Flutter-hosted sample clip (also used by the old demo screen).
const _sampleUrl = 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

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

CollectionReference<Map<String, dynamic>> get _videos => FirebaseFirestore.instance.collection('ani_videos');

// Production only when the run names the project — see the backend comment
// in main().
const _productionTarget = String.fromEnvironment('TEST_AGAINST_PRODUCTION');
bool get _againstProduction =>
    _productionTarget == DefaultFirebaseOptions.currentPlatform.projectId;

/// Seed a video doc directly, pointing at [_sampleUrl] so the player has a
/// real clip to stream.
///
/// The create rule refuses that from a client: a video's urls must be the
/// exact R2 keys the upload grant signs, and a "video" that never went
/// through the upload path is what the rule exists to stop. So fixtures are
/// written with the emulator's owner credential, which bypasses rules; the
/// create rule has its own suite (functions/test/ani_videos_rules.test.js).
/// Production has no such bypass, and fabricating a video there is exactly
/// what the rule forbids, so a production run cannot seed — and says so.
///
/// [raw] replaces fields with REST-encoded values as they are, which is how a
/// test stores a document no client could: one of the wrong shape.
Future<String> _seedVideo({
  required String caption,
  bool isSpoiler = false,
  Map<String, Map<String, dynamic>> raw = const {},
}) async {
  if (_againstProduction) {
    throw StateError('ani_videos_test seeds fixtures with the emulator owner '
        'credential; the create rule refuses fabricated videos in production.');
  }
  final uid = (await AuthService.instance.initAuth()).uid;
  final id = _videos.doc().id;
  final project = DefaultFirebaseOptions.currentPlatform.projectId;
  final res = await http.patch(
    Uri.parse('http://127.0.0.1:8080/v1/projects/$project/databases/(default)/documents/ani_videos/$id'),
    headers: const {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
    body: jsonEncode({
      'fields': {
        'userId': {'stringValue': uid},
        'userName': {'stringValue': ''},
        'userAvatar': {'stringValue': ''},
        'isVerified': {'booleanValue': false},
        'videoUrl': {'stringValue': _sampleUrl},
        'thumbnailUrl': {'stringValue': ''},
        'caption': {'stringValue': caption},
        'anilist_id': {'integerValue': '154587'},
        'animeTitle': {'stringValue': 'Frieren'},
        'hashtags': {'arrayValue': <String, dynamic>{}},
        'durationSeconds': {'integerValue': '10'},
        'likes': {'integerValue': '0'},
        'commentsCount': {'integerValue': '0'},
        'shareCount': {'integerValue': '0'},
        'viewCount': {'integerValue': '0'},
        'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        'isSpoiler': {'booleanValue': isSpoiler},
        ...raw,
      },
    }),
  );
  if (res.statusCode != 200) {
    throw StateError('seeding ani_videos/$id failed: ${res.statusCode} ${res.body}');
  }
  return id;
}

Future<void> _cleanup() async {
  try {
    final uid = (await AuthService.instance.initAuth()).uid;
    final snap = await _videos.where('userId', isEqualTo: uid).get();
    for (final d in snap.docs) {
      // A caption that is not a string is a malformed test video, and the
      // cast that used to be here threw on it and ended the sweep.
      final caption = d.data()['caption'];
      if (caption is! String || caption.startsWith('ZZTest')) {
        await d.reference.delete();
      }
    }
  } catch (_) {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String testerHandle;

  // Emulator by default, like the other UI tests. This test seeds videos,
  // files a report and claims a handle, so running it against the live
  // project is a deliberate opt-in that has to name the project:
  //   --dart-define=TEST_AGAINST_PRODUCTION=anisphere-36cb0
  // Anything else — no define, `=true`, a typo — stays on the emulator. Until
  // 2026-10-02 the default was the live project, and a batch run took that
  // default without anyone choosing it.
  //
  // It defaulted live because firebase-ios-sdk 12.15's gRPC WatchStream
  // failed against cloud-firestore-emulator v1.21 (2026-07-06). That no
  // longer reproduces: this and the other UI tests run on the same emulator.
  final againstProduction = _againstProduction;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (!againstProduction) {
      await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
      FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    }
    debugPrint('[ani_videos_test] backend: '
        '${againstProduction ? 'PRODUCTION ($_productionTarget)' : 'emulator'}');
    await AuthService.instance.initAuth();
    testerHandle = await claimTestHandle('zztester');
    await _cleanup();
  });

  tearDownAll(_cleanup);

  testWidgets('service: feed / like / comment / view / report / delete', (tester) async {
    final svc = AniVideoService.instance;
    final uid = (await AuthService.instance.initAuth()).uid;

    // Over-limit uploads are rejected before any bytes move. The limit, not a
    // literal: it went from 60s to 120s, which left a hard-coded 61 legal.
    await expectLater(
      () => svc.uploadVideo(
        videoFile: File('/nonexistent.mp4'),
        videoId: svc.newVideoId(),
        durationSeconds: AniVideoData.maxDurationSeconds + 1,
        caption: 'too long',
      ),
      throwsArgumentError,
    );

    final videoId = await _seedVideo(caption: _caption);

    // It lands on the first feed page (newest first).
    final feed = await svc.getVideoFeed().first;
    expect(feed.any((v) => v.id == videoId), isTrue);
    var video = (await svc.watchVideo(videoId).first)!;
    expect(video.caption, _caption);
    expect(video.likes, 0);
    expect(video.anilistId, 154587);

    // Like / unlike round trip with counter.
    await svc.likeVideo(videoId, uid);
    expect(await svc.isVideoLikedByUser(videoId, uid), isTrue);
    video = (await svc.watchVideo(videoId).first)!;
    expect(video.likes, 1);
    await svc.unlikeVideo(videoId, uid);
    video = (await svc.watchVideo(videoId).first)!;
    expect(video.likes, 0);

    // Comment / delete comment with counter.
    final commentId = await svc.addComment(videoId, _commentContent);
    var comments = await svc.getComments(videoId).first;
    expect(comments.any((c) => c.id == commentId && c.content == _commentContent), isTrue);
    video = (await svc.watchVideo(videoId).first)!;
    expect(video.commentsCount, 1);
    await svc.deleteComment(videoId, commentId);
    comments = await svc.getComments(videoId).first;
    expect(comments, isEmpty);

    // View bump is debounced to once per session.
    svc.incrementView(videoId);
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      video = (await svc.watchVideo(videoId).first)!;
      if (video.viewCount == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(video.viewCount, 1);
    svc.incrementView(videoId);
    await Future<void>.delayed(const Duration(seconds: 1));
    video = (await svc.watchVideo(videoId).first)!;
    expect(video.viewCount, 1);

    // Share bump and report are accepted.
    svc.incrementShareCount(videoId);
    await svc.reportVideo(videoId, 'spam');

    // Delete runs through the deleteVideoObjects callable, which removes the
    // clip from R2 with the real bucket's credentials. The emulator suite has
    // no R2 and must not reach the real one, so only a production run
    // exercises it. On the emulator the doc is deleted directly, through this
    // client, so it leaves the local cache too: the next test's fixtures are
    // written past the cache, the feed opens on what the cache holds, and the
    // screen keeps the viewer there when the newer videos arrive above it.
    if (againstProduction) {
      await svc.deleteVideo(videoId);
    } else {
      await _videos.doc(videoId).delete();
    }
    expect(await svc.watchVideo(videoId).first, isNull);
  });

  testWidgets('ui: nav restructure + video feed, like, spoiler, comments', (tester) async {
    await _seedVideo(caption: _caption);
    final spoilerId = await _seedVideo(caption: _spoilerCaption, isSpoiler: true);
    expect(spoilerId, isNotEmpty);

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/feed');
    await pumpUntil(tester, find.text('Feed'));

    // New 5-slot bottom nav: Feed | Discover | [+] | Ani Videos | Profile.
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Ani Videos'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // Former tabs are gone from the bar…
    expect(find.text('Trending'), findsNothing);
    expect(find.text('My List'), findsNothing);
    expect(find.text('Rooms'), findsNothing);

    // …and live in the drawer instead. Sync on 'Rooms' — it appears ONLY in
    // the drawer ('Trending'/'My List' have false-positive matches on the
    // feed, e.g. "Trending This Season").
    await tester.tap(find.byIcon(LucideIcons.menu).first);
    await pumpUntil(tester, find.textContaining('Rooms'));
    // Scoped to the drawer: since the emoji went, 'Trending' alone is also a
    // Discover tab label.
    final inDrawer = find.byType(Drawer);
    expect(find.descendant(of: inDrawer, matching: find.text('Trending')), findsOneWidget);
    expect(find.descendant(of: inDrawer, matching: find.text('My List')), findsOneWidget);

    // Drawer → My List still works (former tab, now pushed).
    await tester.tap(find.descendant(of: inDrawer, matching: find.text('My List')));
    await pumpUntil(tester, find.text('Nothing here yet'));
    appRouter.pop();
    // Let the popped route animate fully out — a tap during the transition
    // lands on the still-present My List page instead of the nav bar.
    await pumpUntilGone(tester, find.text('Nothing here yet'));
    await tester.pump(const Duration(milliseconds: 400));

    // Ani Videos tab: newest first → the spoiler video is page 0, blurred.
    await tester.tap(find.text('Ani Videos'));
    await pumpUntil(tester, find.text('Spoiler — tap to reveal'));
    await tester.tap(find.text('Spoiler — tap to reveal'));
    await pumpUntilGone(tester, find.text('Spoiler — tap to reveal'));
    expect(find.textContaining('ZZTest spoiler video'), findsOneWidget);
    expect(find.text('@$testerHandle'), findsWidgets);
    expect(find.text('Frieren'), findsWidgets);

    // Optimistic like: heart fills immediately.
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    final liked = (await AniVideoService.instance.getVideoFeed().first).firstWhere((v) => v.id == spoilerId);
    expect(liked.likes, 1);

    // Comments sheet: send one, it streams back, counter reaches Firestore.
    await tester.tap(find.byIcon(LucideIcons.messageCircle).first);
    await pumpUntil(tester, find.byIcon(LucideIcons.send));
    await tester.enterText(find.byType(TextField).first, _commentContent);
    await tester.tap(find.byIcon(LucideIcons.send));
    await pumpUntil(tester, find.text(_commentContent));
    final commented = (await AniVideoService.instance.watchVideo(spoilerId).first)!;
    expect(commented.commentsCount, 1);
  });

  // A video the rules never admitted — stored before they checked types, or
  // by a path they cannot see — must cost the feed that one video, not the
  // page. Two shapes: a createdAt that is text, which Firestore orders above
  // every timestamp in a newest-first query, so it heads everyone's first
  // page; and a wrong-typed field on a video that sorts normally.
  testWidgets('ui: a malformed video drops out of the feed instead of failing it', (tester) async {
    // Through this client, so the cache forgets the earlier tests' videos too
    // — fixtures below are written past it.
    await _cleanup();
    final goodId = await _seedVideo(caption: _caption);
    final textDateId = await _seedVideo(
      caption: _malformedCaption,
      raw: {'createdAt': {'stringValue': 'zzz'}},
    );
    final textFlagId = await _seedVideo(
      caption: _malformedCaption,
      raw: {'isSpoiler': {'stringValue': 'yes'}},
    );

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/ani-videos');
    final good = find.textContaining('ZZTest video caption');
    final loadError = find.text("Couldn't load videos.");
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end) && good.evaluate().isEmpty && loadError.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(loadError, findsNothing);
    expect(good, findsOneWidget);

    final feed = await AniVideoService.instance
        .getVideoFeed()
        .firstWhere((list) => list.any((v) => v.id == goodId))
        .timeout(const Duration(seconds: 20));
    final ids = feed.map((v) => v.id);
    expect(ids, isNot(contains(textDateId)));
    expect(ids, isNot(contains(textFlagId)));

    // Paging counts what the query returned, not what survived it: a page of
    // three that lost two is still full, so the screen keeps asking for more.
    final page = await AniVideoService.instance
        .watchFeed(limit: 3)
        .firstWhere((p) => p.videos.any((v) => v.id == goodId))
        .timeout(const Duration(seconds: 20));
    expect(page.videos.map((v) => v.id), [goodId]);
    expect(page.full, isTrue);
  });
}
