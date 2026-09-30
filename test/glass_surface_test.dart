import 'package:anisphere/core/constants/app_colors.dart';
import 'package:anisphere/shared/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {bool highContrast = false}) => MediaQuery(
      data: MediaQueryData(highContrast: highContrast),
      child: MaterialApp(home: Scaffold(body: home)),
    );

const _blur = GlassSurface.blur(child: SizedBox(width: 40, height: 40));

BackdropFilter _filter(WidgetTester tester) => tester.widget(find.byType(BackdropFilter));

void _noop() {}

void main() {
  testWidgets('blur inside a GlassLayer joins its group', (tester) async {
    await tester.pumpWidget(_app(const GlassLayer(child: _blur)));
    expect(tester.takeException(), isNull);
    expect(_filter(tester).backdropGroupKey, isNotNull);
  });

  testWidgets('two surfaces in one layer share its key; another layer has its own', (tester) async {
    await tester.pumpWidget(_app(const GlassLayer(
      child: Column(children: [_blur, _blur, GlassLayer(child: _blur)]),
    )));
    final keys = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).map((f) => f.backdropGroupKey).toList();
    expect(keys[0], same(keys[1]));
    expect(keys[2], isNot(same(keys[0])));
  });

  testWidgets('blur with no layer is refused in debug', (tester) async {
    await tester.pumpWidget(_app(_blur));
    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('blur behind a GlassLayerBoundary is refused until it opens its own layer', (tester) async {
    await tester.pumpWidget(_app(const GlassLayer(child: GlassLayerBoundary(child: _blur))));
    expect(tester.takeException(), isA<FlutterError>());

    await tester.pumpWidget(_app(const GlassLayer(child: GlassLayerBoundary(child: GlassLayer(child: _blur)))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog opened inside a layer must open its own', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_app(GlassLayer(child: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }))));

    showDialog<void>(context: ctx, builder: (_) => const Center(child: _blur));
    await tester.pump();
    expect(tester.takeException(), isA<FlutterError>(),
        reason: "the dialog's surface would have shared the screen's layer");
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();

    showDialog<void>(context: ctx, builder: (_) => const Center(child: GlassLayer(child: _blur)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ListTile inside a surface has a Material above the fill', (tester) async {
    // ListTile asserts when a coloured box sits between it and its Material —
    // its splash would paint underneath the fill. Seen in the drawer.
    await tester.pumpWidget(_app(const GlassLayer(
      child: GlassSurface.blur(child: ListTile(title: Text('row'), onTap: _noop)),
    )));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tint never blurs and needs no layer', (tester) async {
    await tester.pumpWidget(_app(const GlassSurface.tint(child: SizedBox(width: 40, height: 40))));
    expect(tester.takeException(), isNull);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('High Contrast renders the opaque surface in both modes, with no blur', (tester) async {
    for (final surface in const [
      GlassSurface.blur(child: SizedBox(width: 40, height: 40)),
      GlassSurface.tint(child: SizedBox(width: 40, height: 40)),
    ]) {
      await tester.pumpWidget(_app(surface, highContrast: true));
      expect(tester.takeException(), isNull, reason: 'no layer is needed when nothing blurs');
      expect(find.byType(BackdropFilter), findsNothing);
      final box = tester.widget<DecoratedBox>(
          find.descendant(of: find.byType(GlassSurface), matching: find.byType(DecoratedBox)).first);
      expect((box.decoration as BoxDecoration).color, AppColors.surface);
    }
  });
}
