// Guards the language sheet against RenderFlex overflow.
//
// The sheet holds a fixed list of 8 languages (464pt of ListTile at default
// text size) inside a modal bottom sheet. Before the fix the sheet was capped
// at 9/16 of the screen — 474.8pt on a 844pt device, 375.2pt on an iPhone SE —
// so the content overflowed on every supported device, and far worse at
// accessibility text sizes.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anisphere/core/constants/app_strings.dart';
import 'package:anisphere/shared/widgets/language_sheet.dart';

/// The Column the RenderFlex error named — reached via the tiles so we measure
/// the sheet's own Column, not a framework box that spans the whole screen.
Finder sheetColumn() =>
    find.ancestor(of: find.byType(ListTile).first, matching: find.byType(Column)).first;

/// Logical sizes for the smallest and largest devices the app targets.
const _iPhoneSE = Size(375, 667);
const _iPhone17ProMax = Size(440, 956);

/// iOS Dynamic Type at the largest accessibility step (AX5).
const _axMaxTextScale = 3.1;

Future<void> openSheet(
  WidgetTester tester, {
  required Size size,
  double textScale = 1.0,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = size * 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      // Above the Navigator, so the modal route inherits both.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showLanguageSheet(c),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('no overflow', () {
    testWidgets('iPhone SE (smallest)', (tester) async {
      await openSheet(tester, size: _iPhoneSE);
      expect(tester.takeException(), isNull);
    });

    testWidgets('iPhone 17 Pro Max (largest)', (tester) async {
      await openSheet(tester, size: _iPhone17ProMax);
      expect(tester.takeException(), isNull);
    });

    testWidgets('largest accessibility text size on the smallest device',
        (tester) async {
      await openSheet(tester, size: _iPhoneSE, textScale: _axMaxTextScale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('largest accessibility text size on the largest device',
        (tester) async {
      await openSheet(tester, size: _iPhone17ProMax, textScale: _axMaxTextScale);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('sheet stays within its height cap and every language is reachable',
      (tester) async {
    await openSheet(tester, size: _iPhoneSE, textScale: _axMaxTextScale);
    expect(tester.takeException(), isNull);

    final sheetHeight = tester.getSize(sheetColumn()).height;
    expect(sheetHeight, lessThanOrEqualTo(_iPhoneSE.height * 0.85 + 0.5));

    // The last language must be scrollable into view rather than clipped away.
    final last = AppStrings.languages.last.name;
    await tester.scrollUntilVisible(find.text(last), 120,
        scrollable: find.byType(Scrollable).last);
    expect(find.text(last), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet hugs its content when the list fits', (tester) async {
    await openSheet(tester, size: _iPhone17ProMax);
    // 956 * 0.85 = 812.6 available; content is ~538, so the sheet must NOT
    // stretch to the cap.
    final h = tester.getSize(sheetColumn()).height;
    expect(h, lessThan(700), reason: 'sheet should size to content, not fill');
  });

  group('Arabic RTL', () {
    testWidgets('does not overflow', (tester) async {
      await openSheet(tester, size: _iPhoneSE, direction: TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrors: flag sits right of the label', (tester) async {
      await openSheet(tester, size: _iPhone17ProMax, direction: TextDirection.rtl);
      final tile = find.byType(ListTile).first;
      final flag = tester.getCenter(
          find.descendant(of: tile, matching: find.text(AppStrings.languages.first.flag)));
      final label = tester.getCenter(
          find.descendant(of: tile, matching: find.text(AppStrings.languages.first.name)));
      expect(flag.dx, greaterThan(label.dx),
          reason: 'in RTL the leading flag must be on the right');
      expect(tester.takeException(), isNull);
    });

    testWidgets('LTR keeps the flag left of the label', (tester) async {
      await openSheet(tester, size: _iPhone17ProMax);
      final tile = find.byType(ListTile).first;
      final flag = tester.getCenter(
          find.descendant(of: tile, matching: find.text(AppStrings.languages.first.flag)));
      final label = tester.getCenter(
          find.descendant(of: tile, matching: find.text(AppStrings.languages.first.name)));
      expect(flag.dx, lessThan(label.dx));
    });
  });
}
