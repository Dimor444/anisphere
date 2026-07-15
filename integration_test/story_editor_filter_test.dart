import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/core/constants/app_colors.dart';
import 'package:anisphere/features/stories/story_editor_screen.dart';
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
  final file = File('${Directory.systemTemp.path}/story_filter_test_base.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

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

int _chroma(int r, int g, int b) => math.max(r, math.max(g, b)) - math.min(r, math.min(g, b));
bool isColorful(int r, int g, int b) => _chroma(r, g, b) > 40;
bool isGrayish(int r, int g, int b) => _chroma(r, g, b) <= 24;
bool isBlue(int r, int g, int b) => b > 150 && r < 100 && g < 100;
bool isRed(int r, int g, int b) => r > 150 && g < 120 && b < 120;
bool isWhite(int r, int g, int b) => r > 190 && g > 190 && b > 190;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;
  final navKey = GlobalKey<NavigatorState>();
  const mentionUid = 'zz-filter-u';

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);

    await AuthService.instance.signOut();
    uid = (await AuthService.instance.initAuth()).uid;

    final res = await http.patch(
      Uri.parse('$_fsBase/users/$mentionUid'),
      headers: _owner,
      body: jsonEncode({
        'fields': {
          'userName': {'stringValue': 'zzfilter_u'},
          'userNameLower': {'stringValue': 'zzfilter_u'},
          'displayName': {'stringValue': 'Filter U'},
          'followerCount': {'integerValue': '1'},
        },
      }),
    );
    expect(res.statusCode, 200, reason: 'seed user failed: ${res.body}');
  });

  tearDownAll(() async {
    await http.delete(Uri.parse('$_fsBase/users/$mentionUid'), headers: _owner);
  });

  setUp(() async {
    final res = await http.get(Uri.parse('$_fsBase/stories'), headers: _owner);
    for (final m in RegExp('"name": "([^"]+/stories/[^"]+)"').allMatches(res.body)) {
      await http.delete(Uri.parse('http://localhost:8080/v1/${m.group(1)}'), headers: _owner);
    }
  });

  Future<void> openEditor(WidgetTester tester, File image) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        navigatorKey: navKey,
        theme: ThemeData.dark(),
        home: const Scaffold(body: SizedBox()),
      ),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryEditorScreen(imageFile: image),
    ));
    await pumpUntil(tester, find.byWidgetPredicate((w) => w is Image && w.image is FileImage));
    await tester.pumpAndSettle();
  }

  /// Selects [name] from the filter strip (opens it if needed).
  Future<void> pickFilter(WidgetTester tester, String name) async {
    if (find.text('Original').evaluate().isEmpty) {
      await tester.tap(find.byIcon(LucideIcons.sparkles));
      await pumpUntil(tester, find.text('Original'));
    }
    await tester.tap(find.text(name));
    await tester.pump();
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>> myStoryDoc() async {
    final snap = await FirebaseFirestore.instance.collection('stories').where('uid', isEqualTo: uid).get();
    expect(snap.docs.length, 1, reason: 'expected exactly one uploaded story');
    return snap.docs.first;
  }

  Future<void> deleteStory(String id) async {
    await FirebaseFirestore.instance.collection('stories').doc(id).delete();
    await FirebaseStorage.instance.ref('stories/$uid/$id.jpg').delete();
  }

  Future<Uint8List> uploadedJpeg(WidgetTester tester, String id) async =>
      (await tester.runAsync(() async => (await FirebaseStorage.instance.ref('stories/$uid/$id.jpg').getData())!))!;

  Future<void> drawLine(WidgetTester tester, Offset a, Offset b, {int steps = 8}) async {
    final gesture = await tester.startGesture(a);
    for (var i = 1; i <= steps; i++) {
      await gesture.moveTo(Offset.lerp(a, b, i / steps)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets('Mono bakes into the upload; back to Original stays untouched', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));

    // Mono: the whole upload must be desaturated (pure blue would scream).
    await openEditor(tester, base!);
    await pickFilter(tester, 'Mono');
    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));
    var doc = await tester.runAsync(myStoryDoc);
    var jpeg = await uploadedJpeg(tester, doc!.id);
    final colorful =
        await tester.runAsync(() => countPixels(jpeg, isColorful, const Rect.fromLTRB(0, 0, 1, 1)));
    expect(colorful, 0, reason: 'Mono upload must contain no saturated pixels');
    final gray = await tester.runAsync(() => countPixels(jpeg, isGrayish, const Rect.fromLTRB(0, 0, 1, 1)));
    expect(gray, greaterThan(100000), reason: 'Mono upload must be gray, not empty/black-failed');
    await tester.runAsync(() => deleteStory(doc!.id));
    // The 'Story shared' snackbar outlives the editor (the messenger state
    // survives pumpWidget re-use of the same MaterialApp) and would absorb
    // the next Share tap — wait it out.
    await pumpWhile(tester, find.textContaining('Story shared'), timeout: const Duration(seconds: 10));

    // Select Mono, then back to Original: identity — the untouched fast
    // path uploads the original pure blue.
    await openEditor(tester, base);
    await pickFilter(tester, 'Mono');
    await pickFilter(tester, 'Original');
    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));
    doc = await tester.runAsync(myStoryDoc);
    jpeg = await uploadedJpeg(tester, doc!.id);
    final nonBlue = await tester.runAsync(
        () => countPixels(jpeg, (r, g, b) => !isBlue(r, g, b), const Rect.fromLTRB(0, 0, 1, 1)));
    expect(nonBlue, 0, reason: 'Original must leave the image exactly as before');
    await tester.runAsync(() => deleteStory(doc!.id));
  });

  testWidgets('filtered base composes under unfiltered stroke, text and mention', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await openEditor(tester, base!);
    final canvas = tester.getRect(find.byWidgetPredicate((w) => w is Image && w.image is FileImage));

    await pickFilter(tester, 'Mono');

    // Red stroke down the left side (draw toggle closes the filter strip).
    await tester.tap(find.byIcon(LucideIcons.brush));
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.error));
    await tester.pump();
    await drawLine(
      tester,
      canvas.topLeft + Offset(canvas.width * 0.25, canvas.height * 0.30),
      canvas.topLeft + Offset(canvas.width * 0.25, canvas.height * 0.70),
    );
    await tester.tap(find.byIcon(LucideIcons.brush));
    await tester.pump();

    // White text, dragged right.
    await tester.tap(find.byIcon(LucideIcons.type));
    await pumpUntil(tester, find.text('Add text'));
    await tester.enterText(find.byType(TextField).last, 'HI');
    await tester.tap(find.text('Done'));
    // Wait for the sheet to fully dismiss — its EditableText also matches
    // 'HI' and would make the drag finder ambiguous.
    await pumpWhile(tester, find.text('Done'));
    await pumpUntil(tester, find.text('HI'));
    await tester.drag(find.text('HI'), Offset(canvas.width * 0.25, 0));
    await tester.pump();

    // Mention sticker, dragged to the upper area. (No pumpAndSettle once a
    // chip exists — UserAvatar's aura animates forever.)
    await tester.tap(find.byIcon(LucideIcons.atSign));
    await pumpUntil(tester, find.byType(TextField));
    await tester.enterText(find.byType(TextField).last, 'zzfilter');
    await pumpUntil(tester, find.text('@zzfilter_u'));
    await tester.tap(find.text('@zzfilter_u'));
    await pumpWhile(tester, find.byType(ListTile));
    await pumpUntil(tester, find.text('@zzfilter_u'));
    await tester.drag(find.text('@zzfilter_u'), Offset(canvas.width * 0.20, -canvas.height * 0.35));
    await tester.pump();

    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final doc = await tester.runAsync(myStoryDoc);
    final story = StoryData.fromDoc(doc!);
    expect(story.mentions.length, 1);
    expect(story.mentions.first.uid, mentionUid);
    final jpeg = await uploadedJpeg(tester, doc.id);

    // Base is filtered everywhere: not a single blue pixel survives, and a
    // region away from every overlay is pure gray.
    final blue =
        await tester.runAsync(() => countPixels(jpeg, isBlue, const Rect.fromLTRB(0, 0, 1, 1)));
    // A handful of blue-ish pixels are JPEG chroma ringing at overlay edges;
    // an unfiltered base would be ~all of the ~580k pixels.
    expect(blue, lessThan(50), reason: 'the filtered base must have no original-blue pixels');
    final strayColor = await tester
        .runAsync(() => countPixels(jpeg, isColorful, const Rect.fromLTRB(0.05, 0.85, 0.95, 0.98)));
    expect(strayColor, 0, reason: 'overlay-free base region must be desaturated');

    // Overlays sit on top UNfiltered: the stroke is still red, the text
    // still white, the mention chip still saturated inside its stored rect.
    final red = await tester
        .runAsync(() => countPixels(jpeg, isRed, const Rect.fromLTRB(0.15, 0.25, 0.35, 0.75)));
    expect(red, greaterThan(100), reason: 'stroke must stay red above the mono base');
    final white = await tester
        .runAsync(() => countPixels(jpeg, isWhite, const Rect.fromLTRB(0.55, 0.35, 0.95, 0.65)));
    expect(white, greaterThan(30), reason: 'text must stay white above the mono base');
    final m = story.mentions.first;
    final sticker = await tester.runAsync(() => countPixels(
        jpeg, isColorful, Rect.fromLTRB(m.x - 0.02, m.y - 0.02, m.x + m.w + 0.02, m.y + m.h + 0.02)));
    expect(sticker, greaterThan(20), reason: 'mention chip must stay saturated inside its rect');

    await tester.runAsync(() => deleteStory(doc.id));
  });
}
