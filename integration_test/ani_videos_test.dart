import 'dart:io';

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
import 'package:anisphere/data/models/ani_video.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/ani_video_service.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';

// 'ZZTest' marker keeps seeded content identifiable for cleanup.
const _caption = 'ZZTest video caption #zzvideotag';
const _spoilerCaption = 'ZZTest spoiler video — the mentor dies';
const _commentContent = 'ZZTest video comment';
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

/// Seed a video doc directly (Storage isn't part of the emulator run; the
/// player streams [_sampleUrl] over the network instead).
Future<String> _seedVideo({required String caption, bool isSpoiler = false}) async {
  final uid = (await AuthService.instance.initAuth()).uid;
  final doc = _videos.doc();
  await doc.set(AniVideoData(
    id: doc.id,
    userId: uid,
    userName: 'ZZTester',
    isVerified: true,
    videoUrl: _sampleUrl,
    caption: caption,
    anilistId: 154587,
    animeTitle: 'Frieren',
    durationSeconds: 10,
    isSpoiler: isSpoiler,
  ).toMap());
  return doc.id;
}

Future<void> _cleanup() async {
  try {
    final uid = (await AuthService.instance.initAuth()).uid;
    final snap = await _videos.where('userId', isEqualTo: uid).get();
    for (final d in snap.docs) {
      if ((d.data()['caption'] as String? ?? '').startsWith('ZZTest')) {
        await d.reference.delete();
      }
    }
  } catch (_) {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Live-project run (like production_smoke_test): all seeded docs carry the
  // ZZTest marker and are removed in tearDownAll. The emulator would be
  // preferable, but firebase-ios-sdk 12.15's gRPC WatchStream fails against
  // cloud-firestore-emulator v1.21 ('Unknown: An internal error') — verified
  // 2026-07-06 with a raw TCP probe (socket connects; gRPC handshake dies).
  // Flip with --dart-define=USE_EMULATOR=true once that incompatibility is
  // fixed upstream.
  const useEmulator = bool.fromEnvironment('USE_EMULATOR');

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (useEmulator) {
      await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
      FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    }
    await AuthService.instance.initAuth();
    await FollowService.instance.ensureProfile(userName: 'ZZTester');
    await _cleanup();
  });

  tearDownAll(_cleanup);

  testWidgets('service: feed / like / comment / view / report / delete', (tester) async {
    final svc = AniVideoService.instance;
    final uid = (await AuthService.instance.initAuth()).uid;

    // >60s uploads are rejected before any bytes move.
    await expectLater(
      () => svc.uploadVideo(
        videoFile: File('/nonexistent.mp4'),
        durationSeconds: 61,
        caption: 'too long',
        userName: 'ZZTester',
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
    final commentId = await svc.addComment(videoId, _commentContent, userName: 'ZZTester');
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

    // Delete (Storage cleanup inside is best-effort and must not throw).
    await svc.deleteVideo(videoId);
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
    expect(find.text('🔥 Trending'), findsOneWidget);
    expect(find.text('📺 My List'), findsOneWidget);

    // Drawer → My List still works (former tab, now pushed).
    await tester.tap(find.text('📺 My List'));
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
    expect(find.text('@ZZTester'), findsWidgets);
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
}
