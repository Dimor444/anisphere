import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/shared/widgets/bottom_nav_bar.dart';
import 'package:anisphere/shared/widgets/gradient_button.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Stands in for the native photo picker, which a test cannot drive: hands
/// back [path] and records the source the app asked for.
class _FakePicker extends ImagePickerPlatform {
  _FakePicker(this.path);
  final String path;
  final asked = <ImageSource>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    asked.add(source);
    return XFile(path);
  }
}

/// Settings shows no privacy control that nothing enforces, and the create
/// sheet's Add Story is the real story flow, through to a published story.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await FirebaseStorage.instance.useStorageEmulator('127.0.0.1', 9199);
    uid = await freshGuest();
    await claimTestHandle('zzprivacy');
  });

  testWidgets('ui: Settings shows no privacy control that does nothing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    appRouter.go('/settings');
    await pumpUntil(tester, find.text('Settings'));
    for (final label in [
      'Privacy',
      'Private account',
      'Who can DM',
      'Show streak',
      'Show True Fan rank',
      'Birthday visibility',
    ]) {
      expect(find.text(label, skipOffstage: false), findsNothing, reason: label);
    }
    expect(find.byType(Switch, skipOffstage: false), findsNothing);
    expect(find.byType(DropdownButton<String>, skipOffstage: false), findsNothing);

    // Block List works, and stays.
    await tester.scrollUntilVisible(find.text('Block List'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Block List'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("ui: the create sheet's Add Story publishes a story", (tester) async {
    final photo = File('${Directory.systemTemp.path}/zz_add_story_photo.png');
    await photo.writeAsBytes((await rootBundle.load('assets/icons/app_icon.png')).buffer.asUint8List());
    final picker = _FakePicker(photo.path);
    ImagePickerPlatform.instance = picker;

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    appRouter.go('/discover');
    final fab = find.descendant(of: find.byType(AniBottomNav), matching: find.byIcon(LucideIcons.plus));
    await pumpUntil(tester, fab);
    await tester.tap(fab);
    // The create sheet's row, not the feed's Add Story button.
    await pumpUntil(tester, find.text('24-hour story'));
    await tester.tap(find.text('24-hour story'));

    // The create sheet has closed; the flow it started carries on.
    await pumpUntil(tester, find.text('Choose from gallery'));
    await tester.tap(find.text('Choose from gallery'));
    final share = find.byWidgetPredicate(
        (w) => w is GradientButton && w.label == 'Share to Story' && w.onPressed != null);
    await pumpUntil(tester, share);
    // The editor slides up from below; a tap before it arrives lands off
    // the screen and hits nothing.
    final screen = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (!screen.contains(tester.getCenter(share)) && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(share);
    await pumpUntil(tester, find.text('Story shared — it disappears in 24h.'), timeout: const Duration(seconds: 40));

    expect(picker.asked, [ImageSource.gallery]);
    final mine = await FirebaseFirestore.instance.collection('stories').where('uid', isEqualTo: uid).get();
    expect(mine.docs, hasLength(1));
    final stored = await FirebaseStorage.instance.ref('stories/$uid/${mine.docs.single.id}.jpg').getMetadata();
    expect(stored.contentType, 'image/jpeg');
    expect(tester.takeException(), isNull);
  });
}
