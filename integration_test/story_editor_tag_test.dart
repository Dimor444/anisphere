import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/core/utils/post_image_compressor.dart';
import 'package:anisphere/features/stories/story_editor_screen.dart';
import 'package:anisphere/features/stories/story_providers.dart';
import 'package:anisphere/features/stories/story_viewer_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/story_service.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> pumpWhile(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to go away');
}

Future<File> makeBaseImage(Color color, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = color,
  );
  final img = await recorder.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final file = File('${Directory.systemTemp.path}/story_tag_test_base.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

/// Counts pixels matching [test] in the fractional rect [region] of [jpeg].
Future<int> countPixels(List<int> jpeg, bool Function(int r, int g, int b) test, Rect region) async {
  final img = await decodeImageFromList(Uint8List.fromList(jpeg));
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final w = img.width, h = img.height;
  img.dispose();
  var count = 0;
  for (var y = (region.top.clamp(0.0, 1.0) * h).round(); y < (region.bottom.clamp(0.0, 1.0) * h).round(); y++) {
    for (var x = (region.left.clamp(0.0, 1.0) * w).round(); x < (region.right.clamp(0.0, 1.0) * w).round(); x++) {
      final i = (y * w + x) * 4;
      if (test(data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2))) count++;
    }
  }
  return count;
}

bool isNotBlue(int r, int g, int b) => !(b > 150 && r < 100 && g < 100);

/// Live AniList search with retries — this network's DNS drops names
/// intermittently, and the service deliberately doesn't cache failures.
Future<void> searchWithRetry(WidgetTester tester, String query) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    await tester.enterText(find.byType(TextField).last, query);
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 150));
      if (find.byType(ListTile).evaluate().isNotEmpty) return;
    }
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump(const Duration(milliseconds: 400));
  }
  fail('AniList search returned no results for "$query" after 3 attempts');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;
  final navKey = GlobalKey<NavigatorState>();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data (AniList search is live).
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);

    await AuthService.instance.signOut();
    uid = (await AuthService.instance.initAuth()).uid;
  });

  setUp(() async {
    const base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
    const owner = {'Authorization': 'Bearer owner'};
    final res = await http.get(Uri.parse('$base/stories'), headers: owner);
    for (final m in RegExp('"name": "([^"]+/stories/[^"]+)"').allMatches(res.body)) {
      await http.delete(Uri.parse('http://localhost:8080/v1/${m.group(1)}'), headers: owner);
    }
  });

  Future<QueryDocumentSnapshot<Map<String, dynamic>>> myStoryDoc() async {
    final snap = await FirebaseFirestore.instance.collection('stories').where('uid', isEqualTo: uid).get();
    expect(snap.docs.length, 1, reason: 'expected exactly one uploaded story');
    return snap.docs.first;
  }

  Future<void> deleteStory(String id) async {
    await FirebaseFirestore.instance.collection('stories').doc(id).delete();
    await FirebaseStorage.instance.ref('stories/$uid/$id.jpg').delete();
  }

  testWidgets('tagged story: sticker bakes where dropped and the doc rect frames it', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: navKey,
        theme: ThemeData.dark(),
        home: const Scaffold(body: SizedBox()),
      ),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryEditorScreen(imageFile: base!),
    ));
    await pumpUntil(tester, find.byType(Image));
    await tester.pumpAndSettle();

    // Tag an anime through the shared AniList picker (live search).
    await tester.tap(find.byIcon(LucideIcons.tag));
    await pumpUntil(tester, find.byType(TextField));
    await searchWithRetry(tester, 'Frieren');
    await tester.tap(find.byType(ListTile).first);
    // Let the picker sheet finish dismissing so only the sticker's poster
    // remains; the canvas base image is the sole FileImage-backed Image.
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.byType(CachedNetworkImage));
    final baseImage = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);

    // Drag it into the upper-left area: center 0.5,0.5 → ~0.25,0.20.
    final canvas = tester.getRect(baseImage);
    await tester.drag(find.byType(CachedNetworkImage), Offset(-canvas.width * 0.25, -canvas.height * 0.30));
    await tester.pump();

    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final doc = await tester.runAsync(myStoryDoc);
    final tag = StoryAnimeTag.fromMap(doc!.data()['animeTag']);
    expect(tag, isNotNull, reason: 'doc must carry the structured animeTag');
    expect(tag!.anilistId, greaterThan(0));
    final cx = tag.x + tag.w / 2, cy = tag.y + tag.h / 2;
    expect((cx - 0.25).abs(), lessThan(0.07), reason: 'stored rect center x must match the drop point');
    expect((cy - 0.20).abs(), lessThan(0.07), reason: 'stored rect center y must match the drop point');

    // Self-consistency: every non-blue (sticker) pixel of the upload lies
    // inside the stored rect (small inflation for JPEG edge artifacts), and
    // the rect isn't empty of sticker pixels.
    final jpeg = await tester.runAsync(() async =>
        (await FirebaseStorage.instance.ref('stories/$uid/${doc.id}.jpg').getData())!);
    final inflated = Rect.fromLTRB(tag.x - 0.03, tag.y - 0.03, tag.x + tag.w + 0.03, tag.y + tag.h + 0.03);
    final inRect = await tester.runAsync(() => countPixels(jpeg!, isNotBlue, inflated));
    final everywhere = await tester.runAsync(() => countPixels(jpeg!, isNotBlue, const Rect.fromLTRB(0, 0, 1, 1)));
    expect(inRect, greaterThan(100), reason: 'baked sticker pixels expected inside the stored rect');
    expect(everywhere, inRect, reason: 'no sticker pixels may fall outside the stored rect');

    await tester.runAsync(() => deleteStory(doc.id));
  });

  testWidgets('viewer hotspot maps the normalized rect on a different screen size and deep-links', (tester) async {
    // Author a tagged story directly with a known rect (no editor involved).
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    const knownTag = StoryAnimeTag(anilistId: 5114, x: 0.1, y: 0.2, w: 0.3, h: 0.1);
    final storyId = await tester.runAsync(() async {
      final jpeg = await PostImageCompressor.compress(base!.path);
      return StoryService.instance.createStory(jpeg, animeTag: knownTag);
    });
    final doc = await tester.runAsync(
        () => FirebaseFirestore.instance.collection('stories').doc(storyId).get());
    final story = StoryData.fromDoc(doc!);
    expect(story.animeTag?.anilistId, 5114);

    // Viewer constrained to 300x500 — deliberately NOT the authoring size.
    final pushedIds = <String>[];
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Center(
          child: SizedBox(
            width: 300,
            height: 500,
            child: StoryViewerScreen(group: StoryGroup(uid: uid, stories: [story])),
          ),
        ),
      ),
      GoRoute(
        path: '/trending/anime/:id', // same pattern as the app router
        builder: (_, s) {
          pushedIds.add(s.pathParameters['id'] ?? '');
          return Scaffold(body: Center(child: Text('detail-${s.pathParameters['id']}')));
        },
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp.router(routerConfig: router, theme: ThemeData.dark()),
    ));

    // Wait for the story image to load (hotspot exists only after the image
    // size resolves) — the loading spinner must be gone first.
    await pumpUntil(tester, find.byType(StoryViewerScreen));
    await pumpWhile(tester, find.byType(CircularProgressIndicator), timeout: const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 400));

    // Independent mapping: image 540x1080 contain-fitted in 300x500 →
    // fitted 250x500 at left=25. Hotspot center = (25 + (0.1+0.15)*250,
    // (0.2+0.05)*500) = (87.5, 125) inside the viewer box.
    final viewerBox = tester.getRect(find.byType(StoryViewerScreen));
    await tester.tapAt(viewerBox.topLeft + const Offset(87.5, 125));
    await pumpUntil(tester, find.text('detail-5114'), timeout: const Duration(seconds: 10));
    expect(pushedIds, ['5114'], reason: 'hotspot must deep-link via /trending/anime/:id exactly once');

    await tester.runAsync(() => deleteStory(storyId!));
  });
}
