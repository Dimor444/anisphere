import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/core/constants/app_colors.dart';
import 'package:anisphere/features/stories/story_editor_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';

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

/// A solid-color JPEG-decodable PNG written to a temp file — the "picked
/// photo". Solid color makes baked-text pixel assertions trivial.
Future<File> makeBaseImage(Color color, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = color,
  );
  final img = await recorder.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final file = File('${Directory.systemTemp.path}/story_editor_test_base.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

/// Decodes [jpeg] and counts pixels matching [test] inside the fractional
/// rect [l,t,r,b] (0-1 of image size).
Future<int> countPixels(
  List<int> jpeg,
  bool Function(int r, int g, int b) test, {
  required double l,
  required double t,
  required double r,
  required double b,
}) async {
  final img = await decodeImageFromList(Uint8List.fromList(jpeg));
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final w = img.width, h = img.height;
  img.dispose();
  var count = 0;
  for (var y = (t * h).round(); y < (b * h).round(); y++) {
    for (var x = (l * w).round(); x < (r * w).round(); x++) {
      final i = (y * w + x) * 4;
      if (test(data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2))) count++;
    }
  }
  return count;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;
  final navKey = GlobalKey<NavigatorState>();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseStorage.instance.useStorageEmulator('localhost', 9199);

    await AuthService.instance.signOut();
    uid = (await AuthService.instance.initAuth()).uid;
  });

  // Leftovers from a failed earlier run must not break "exactly one doc".
  setUp(() async {
    const base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
    const owner = {'Authorization': 'Bearer owner'};
    final res = await http.get(Uri.parse('$base/stories'), headers: owner);
    for (final m in RegExp('"name": "([^"]+/stories/[^"]+)"').allMatches(res.body)) {
      await http.delete(Uri.parse('http://localhost:8080/v1/${m.group(1)}'), headers: owner);
    }
  });

  Future<void> openEditor(WidgetTester tester, File image) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      theme: ThemeData.dark(),
      home: const Scaffold(body: SizedBox()),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => StoryEditorScreen(imageFile: image),
    ));
    // Editor open + image decoded (canvas Image appears once aspect is known),
    // then let the fullscreen-dialog slide-up finish — taps during the route
    // transition land on translated (partly off-screen) positions.
    await pumpUntil(tester, find.byType(Image));
    await tester.pumpAndSettle();
  }

  /// The story doc this test run just created (docs are cleaned per test).
  Future<QueryDocumentSnapshot<Map<String, dynamic>>> myStoryDoc() async {
    final snap = await FirebaseFirestore.instance.collection('stories').where('uid', isEqualTo: uid).get();
    expect(snap.docs.length, 1, reason: 'expected exactly one uploaded story');
    return snap.docs.first;
  }

  Future<void> deleteStory(String id) async {
    await FirebaseFirestore.instance.collection('stories').doc(id).delete();
    await FirebaseStorage.instance.ref('stories/$uid/$id.jpg').delete();
  }

  testWidgets('text overlay is baked into the uploaded image where dropped', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await openEditor(tester, base!);

    // Add text via the toolbar.
    await tester.tap(find.byIcon(LucideIcons.type));
    await pumpUntil(tester, find.text('Add text'));
    await tester.enterText(find.byType(TextField).last, 'HELLO');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('HELLO'));

    // Newly added item is selected: recolor it red via the swatch row.
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.error));
    await tester.pump();

    // Drag it into the upper-left quadrant (from canvas center to 25%/25%).
    final canvas = tester.getRect(find.byType(Image));
    await tester.drag(find.text('HELLO'), Offset(-canvas.width * 0.25, -canvas.height * 0.25));
    await tester.pump();

    // Caption + share.
    await tester.enterText(find.widgetWithText(TextField, 'Add a caption (optional)…'), 'flatten proof');
    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final doc = await tester.runAsync(myStoryDoc);
    expect(doc!.data()['caption'], 'flatten proof');
    final jpeg = await tester.runAsync(() async =>
        (await FirebaseStorage.instance.ref('stories/$uid/${doc.id}.jpg').getData())!);

    // Red text pixels must exist around the drop point (upper-left quadrant)…
    final hit = await tester.runAsync(() => countPixels(
        jpeg!, (r, g, b) => r > 150 && g < 120 && b < 120,
        l: 0.02, t: 0.02, r: 0.48, b: 0.48));
    expect(hit, greaterThan(50), reason: 'baked red text expected in the upper-left quadrant');
    // …and nowhere near the opposite quadrant (nothing else was drawn).
    final miss = await tester.runAsync(() => countPixels(
        jpeg!, (r, g, b) => r > 150 && g < 120 && b < 120,
        l: 0.52, t: 0.52, r: 0.98, b: 0.98));
    expect(miss, 0, reason: 'no text was placed in the lower-right quadrant');

    await tester.runAsync(() => deleteStory(doc.id));
  });

  testWidgets('plain photo story (no overlays) uploads unmodified-looking', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await openEditor(tester, base!);

    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final doc = await tester.runAsync(myStoryDoc);
    expect(doc!.data()['caption'], isNull);
    final jpeg = await tester.runAsync(() async =>
        (await FirebaseStorage.instance.ref('stories/$uid/${doc.id}.jpg').getData())!);

    // Uniformly the base blue — nothing baked in anywhere.
    final nonBlue = await tester.runAsync(() => countPixels(
        jpeg!, (r, g, b) => !(b > 150 && r < 100 && g < 100),
        l: 0.0, t: 0.0, r: 1.0, b: 1.0));
    expect(nonBlue, 0, reason: 'plain story must be the untouched base image');

    await tester.runAsync(() => deleteStory(doc.id));
  });

  testWidgets('edit, resize and delete act on the selected text item', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await openEditor(tester, base!);

    // Add.
    await tester.tap(find.byIcon(LucideIcons.type));
    await pumpUntil(tester, find.text('Add text'));
    await tester.enterText(find.byType(TextField).last, 'first');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('first'));

    // Resize via the slider (item is selected right after adding).
    double fontSizeOf(String text) => tester.widget<Text>(find.text(text)).style!.fontSize!;
    final before = fontSizeOf('first');
    await tester.drag(find.byType(Slider), const Offset(0, -60));
    await tester.pump();
    expect(fontSizeOf('first'), greaterThan(before), reason: 'slider must grow the selected text');

    // Tap the selected item again → edit sheet with the current string.
    await tester.tap(find.text('first'));
    await pumpUntil(tester, find.text('Edit text'));
    await tester.enterText(find.byType(TextField).last, 'second');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('second'));
    expect(find.text('first'), findsNothing);

    // Delete via the badge on the selected item.
    final deleteBadge = find.descendant(
        of: find.byWidgetPredicate((w) => w is Stack && w.clipBehavior == Clip.none),
        matching: find.byIcon(LucideIcons.x));
    await tester.tap(deleteBadge);
    await tester.pump();
    expect(find.text('second'), findsNothing);

    // Leave without sharing.
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
  });
}
