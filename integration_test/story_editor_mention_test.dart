import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

const _fsBase = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
const _owner = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

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
  final file = File('${Directory.systemTemp.path}/story_mention_test_base.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

/// Counts pixels matching [test] in the fractional [region] of [jpeg].
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

Future<void> seedUser(String uid, String handle, String display, int followers) async {
  final res = await http.patch(
    Uri.parse('$_fsBase/users/$uid'),
    headers: _owner,
    body: jsonEncode({
      'fields': {
        'userName': {'stringValue': handle},
        'userNameLower': {'stringValue': handle},
        'displayName': {'stringValue': display},
        'followerCount': {'integerValue': '$followers'},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed user failed: ${res.body}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;
  final navKey = GlobalKey<NavigatorState>();
  const uidA = 'zz-mention-a', uidB = 'zz-mention-b';

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);

    await AuthService.instance.signOut();
    uid = (await AuthService.instance.initAuth()).uid;
    await seedUser(uidA, 'zzmention_a', 'Mention A', 5);
    await seedUser(uidB, 'zzmention_b', 'Mention B', 1);
  });

  tearDownAll(() async {
    await http.delete(Uri.parse('$_fsBase/users/$uidA'), headers: _owner);
    await http.delete(Uri.parse('$_fsBase/users/$uidB'), headers: _owner);
  });

  setUp(() async {
    final res = await http.get(Uri.parse('$_fsBase/stories'), headers: _owner);
    for (final m in RegExp('"name": "([^"]+/stories/[^"]+)"').allMatches(res.body)) {
      await http.delete(Uri.parse('http://localhost:8080/v1/${m.group(1)}'), headers: _owner);
    }
  });

  Future<void> deleteStory(String id) async {
    await FirebaseFirestore.instance.collection('stories').doc(id).delete();
    await FirebaseStorage.instance.ref('stories/$uid/$id.jpg').delete();
  }

  Future<void> addMention(WidgetTester tester, String handle, Offset dragBy) async {
    await tester.tap(find.byIcon(LucideIcons.atSign));
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField).last, 'zzmention');
    await pumpUntil(tester, find.text('@$handle'));
    await tester.tap(find.text('@$handle'));
    // Wait for the picker sheet to fully dismiss (its own row would shadow
    // the canvas chip for the same handle text). No pumpAndSettle here: the
    // chip's UserAvatar aura animates forever, so settle never returns.
    await pumpWhile(tester, find.byType(ListTile));
    await pumpUntil(tester, find.text('@$handle'));
    await tester.drag(find.text('@$handle'), dragBy);
    await tester.pump();
  }

  testWidgets('two mention stickers bake where dropped; doc rects frame them', (tester) async {
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
    final canvas = tester.getRect(find.byWidgetPredicate((w) => w is Image && w.image is FileImage));

    // Mention A → upper-left (center 0.25, 0.20); B → lower-right-ish
    // (spawn staggers +40px, drag accounts relative to center).
    await addMention(tester, 'zzmention_a', Offset(-canvas.width * 0.25, -canvas.height * 0.30));
    await addMention(tester, 'zzmention_b', Offset(canvas.width * 0.20, canvas.height * 0.20 - 40));

    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final snap = await tester.runAsync(
        () => FirebaseFirestore.instance.collection('stories').where('uid', isEqualTo: uid).get());
    expect(snap!.docs.length, 1);
    final doc = snap.docs.first;
    final story = StoryData.fromDoc(doc);
    expect(story.mentions.length, 2, reason: 'doc must carry both mentions');
    final byUid = {for (final m in story.mentions) m.uid: m};
    expect(byUid.keys, containsAll([uidA, uidB]));

    final a = byUid[uidA]!, b = byUid[uidB]!;
    expect(((a.x + a.w / 2) - 0.25).abs(), lessThan(0.07), reason: 'mention A rect x-center');
    expect(((a.y + a.h / 2) - 0.20).abs(), lessThan(0.07), reason: 'mention A rect y-center');
    expect(((b.x + b.w / 2) - 0.70).abs(), lessThan(0.07), reason: 'mention B rect x-center');
    expect(((b.y + b.h / 2) - 0.70).abs(), lessThan(0.07), reason: 'mention B rect y-center');

    // Pixel self-consistency: sticker pixels inside each rect, and nothing
    // baked outside the union of the two (inflated) rects.
    final jpeg = await tester.runAsync(() async =>
        (await FirebaseStorage.instance.ref('stories/$uid/${doc.id}.jpg').getData())!);
    Rect inflate(StoryMention m) =>
        Rect.fromLTRB(m.x - 0.03, m.y - 0.03, m.x + m.w + 0.03, m.y + m.h + 0.03);
    final inA = await tester.runAsync(() => countPixels(jpeg!, isNotBlue, inflate(a)));
    final inB = await tester.runAsync(() => countPixels(jpeg!, isNotBlue, inflate(b)));
    final everywhere =
        await tester.runAsync(() => countPixels(jpeg!, isNotBlue, const Rect.fromLTRB(0, 0, 1, 1)));
    expect(inA, greaterThan(50), reason: 'mention A pixels inside its rect');
    expect(inB, greaterThan(50), reason: 'mention B pixels inside its rect');
    expect(everywhere, inA! + inB!, reason: 'no sticker pixels outside the stored rects');

    await tester.runAsync(() => deleteStory(doc.id));
  });

  testWidgets('viewer: anime + mention hotspots each deep-link on a different screen size', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    const tag = StoryAnimeTag(anilistId: 5114, x: 0.55, y: 0.05, w: 0.30, h: 0.08);
    const mentions = [
      StoryMention(uid: uidA, x: 0.1, y: 0.2, w: 0.3, h: 0.1),
      StoryMention(uid: uidB, x: 0.1, y: 0.6, w: 0.3, h: 0.1),
    ];
    final storyId = await tester.runAsync(() async {
      final jpeg = await PostImageCompressor.compress(base!.path);
      return StoryService.instance.createStory(jpeg, animeTag: tag, mentions: mentions);
    });
    final doc = await tester.runAsync(
        () => FirebaseFirestore.instance.collection('stories').doc(storyId).get());
    final story = StoryData.fromDoc(doc!);
    expect(story.mentions.length, 2);

    // Image 540x1080 contain-fitted in a 300x500 box (NOT the authoring
    // size): fitted 250x500 at left=25 → hotspot centers computed
    // independently of the app code.
    const targets = [
      (offset: Offset(87.5, 125), marker: 'profile-$uidA'), // mention A
      (offset: Offset(87.5, 325), marker: 'profile-$uidB'), // mention B
      (offset: Offset(200, 45), marker: 'anime-5114'), // anime tag
    ];
    for (final t in targets) {
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
        // Same patterns as the app router.
        GoRoute(
          path: '/trending/anime/:id',
          builder: (_, s) => Scaffold(body: Center(child: Text('anime-${s.pathParameters['id']}'))),
        ),
        GoRoute(
          path: '/profile/:userId',
          builder: (_, s) => Scaffold(body: Center(child: Text('profile-${s.pathParameters['userId']}'))),
        ),
      ]);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(routerConfig: router, theme: ThemeData.dark()),
      ));
      await pumpUntil(tester, find.byType(StoryViewerScreen));
      await pumpWhile(tester, find.byType(CircularProgressIndicator), timeout: const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 300));

      final viewerBox = tester.getRect(find.byType(StoryViewerScreen));
      await tester.tapAt(viewerBox.topLeft + t.offset);
      await pumpUntil(tester, find.text(t.marker), timeout: const Duration(seconds: 10));
    }

    await tester.runAsync(() => deleteStory(storyId!));
  });
}
