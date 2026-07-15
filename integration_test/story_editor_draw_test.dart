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

Future<File> makeBaseImage(Color color, int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..color = color,
  );
  final img = await recorder.endRecording().toImage(w, h);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  final file = File('${Directory.systemTemp.path}/story_draw_test_base.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  return file;
}

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

bool isRed(int r, int g, int b) => r > 150 && g < 120 && b < 120;
bool isGreen(int r, int g, int b) => g > 150 && r < 100 && b < 150;
bool isWhite(int r, int g, int b) => r > 190 && g > 190 && b > 190;

/// Freehand line from [a] to [b] in global coordinates, in small steps so the
/// pan recognizer emits intermediate updates like a real finger.
Future<void> drawLine(WidgetTester tester, Offset a, Offset b, {int steps = 8}) async {
  final gesture = await tester.startGesture(a);
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(Offset.lerp(a, b, i / steps)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
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
    await pumpUntil(tester, find.byType(Image));
    await tester.pumpAndSettle();
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

  testWidgets('stroke bakes into the uploaded image at position, color and width', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await openEditor(tester, base!);

    // Enter draw mode, pick red, widen the brush via the shared slider.
    await tester.tap(find.byIcon(LucideIcons.brush));
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.error));
    await tester.pump();
    final widthBefore = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.drag(find.byType(Slider), const Offset(0, -60));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(widthBefore),
        reason: 'slider must widen the brush in draw mode');

    // One diagonal stroke across the upper-left quadrant.
    final canvas = tester.getRect(find.byType(Image));
    await drawLine(
      tester,
      canvas.topLeft + Offset(canvas.width * 0.10, canvas.height * 0.10),
      canvas.topLeft + Offset(canvas.width * 0.40, canvas.height * 0.40),
    );

    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final doc = await tester.runAsync(myStoryDoc);
    final jpeg = await uploadedJpeg(tester, doc!.id);

    final hit = await tester.runAsync(() => countPixels(jpeg, isRed, l: 0.04, t: 0.04, r: 0.46, b: 0.46));
    expect(hit, greaterThan(100), reason: 'baked red stroke expected in the upper-left quadrant');
    final miss = await tester.runAsync(() => countPixels(jpeg, isRed, l: 0.52, t: 0.52, r: 0.98, b: 0.98));
    expect(miss, 0, reason: 'nothing was drawn in the lower-right quadrant');

    await tester.runAsync(() => deleteStory(doc.id));
  });

  testWidgets('text + drawing compose; undo removes the last stroke; modes toggle', (tester) async {
    final base = await tester.runAsync(() => makeBaseImage(const Color(0xFF0000FF), 1000, 2000));
    await openEditor(tester, base!);
    final canvas = tester.getRect(find.byType(Image));

    // Stroke 1 (red, keeps): vertical line on the left side.
    await tester.tap(find.byIcon(LucideIcons.brush));
    await tester.pump();
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.error));
    await tester.pump();
    await drawLine(
      tester,
      canvas.topLeft + Offset(canvas.width * 0.25, canvas.height * 0.25),
      canvas.topLeft + Offset(canvas.width * 0.25, canvas.height * 0.75),
    );

    // Stroke 2 (green, undone): lower-right quadrant.
    await tester.tap(find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.success));
    await tester.pump();
    await drawLine(
      tester,
      canvas.topLeft + Offset(canvas.width * 0.60, canvas.height * 0.60),
      canvas.topLeft + Offset(canvas.width * 0.90, canvas.height * 0.90),
    );
    await tester.tap(find.byIcon(LucideIcons.undo2));
    await tester.pump();

    // Leave draw mode; text add + drag must work again (white, to the right).
    await tester.tap(find.byIcon(LucideIcons.brush));
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.type));
    await pumpUntil(tester, find.text('Add text'));
    await tester.enterText(find.byType(TextField).last, 'HI');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('HI'));
    await tester.drag(find.text('HI'), Offset(canvas.width * 0.25, 0));
    await tester.pump();

    await tester.tap(find.text('Share to Story'));
    await pumpWhile(tester, find.byType(StoryEditorScreen));

    final doc = await tester.runAsync(myStoryDoc);
    final jpeg = await uploadedJpeg(tester, doc!.id);

    final red = await tester.runAsync(() => countPixels(jpeg, isRed, l: 0.15, t: 0.20, r: 0.35, b: 0.80));
    expect(red, greaterThan(100), reason: 'kept red stroke expected on the left side');
    final green = await tester.runAsync(() => countPixels(jpeg, isGreen, l: 0.0, t: 0.0, r: 1.0, b: 1.0));
    expect(green, 0, reason: 'undone green stroke must not be baked anywhere');
    final white = await tester.runAsync(() => countPixels(jpeg, isWhite, l: 0.55, t: 0.35, r: 0.98, b: 0.65));
    expect(white, greaterThan(30), reason: 'dragged text expected on the right side');

    await tester.runAsync(() => deleteStory(doc.id));
  });
}
