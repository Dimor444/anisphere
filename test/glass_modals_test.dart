import 'package:anisphere/core/constants/app_colors.dart';
import 'package:anisphere/shared/widgets/glass_modals.dart';
import 'package:anisphere/shared/widgets/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A screen with its own glass layer and one blurred surface — the shell's
/// situation — plus a context to open modals from.
Future<BuildContext> _screen(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GlassLayer(
        child: Builder(builder: (c) {
          ctx = c;
          return const Align(
            alignment: Alignment.bottomCenter,
            child: GlassSurface.blur(child: SizedBox(height: 60, width: 400)),
          );
        }),
      ),
    ),
  ));
  return ctx;
}

List<BackdropFilter> _filters(WidgetTester tester) =>
    tester.widgetList<BackdropFilter>(find.byType(BackdropFilter)).toList();

void main() {
  testWidgets('a glass sheet opens its own layer, not the screen\'s', (tester) async {
    final ctx = await _screen(tester);
    showGlassSheet<void>(context: ctx, builder: (_) => const SizedBox(height: 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the foundation refuses a modal without its own layer');
    final filters = _filters(tester);
    expect(filters, hasLength(2), reason: "the screen's surface and the sheet");
    expect(filters[0].backdropGroupKey, isNot(same(filters[1].backdropGroupKey)));
  });

  testWidgets('blur: false gives the sheet the fill and no blur', (tester) async {
    final ctx = await _screen(tester);
    showGlassSheet<void>(context: ctx, blur: false, builder: (_) => const SizedBox(height: 200));
    await tester.pumpAndSettle();
    expect(_filters(tester), hasLength(1), reason: "only the screen's own surface");
  });

  testWidgets('a glass dialog is one blurred surface: the backdrop, with a tinted dialog on it', (tester) async {
    final ctx = await _screen(tester);
    showGlassDialog<void>(context: ctx, builder: (_) => const AlertDialog(title: Text('Sure?')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(GlassBackdrop), findsOneWidget);
    expect(_filters(tester), hasLength(2), reason: "the screen's surface and the backdrop — the dialog adds none");
    final material = tester.widget<Material>(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first);
    expect(material.color, AppColors.glassFillStrong);
  });

  testWidgets('the dialog backdrop covers the whole screen, safe areas included', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 150, bottom: 100);
    addTearDown(tester.view.resetPadding);
    final ctx = await _screen(tester);
    showGlassDialog<void>(context: ctx, builder: (_) => const AlertDialog(title: Text('Sure?')));
    await tester.pumpAndSettle();
    final screen = tester.getRect(find.byType(Scaffold));
    expect(tester.getRect(find.byType(GlassBackdrop)), screen,
        reason: 'the route SafeArea must not inset the blur');
  });

  testWidgets('tapping outside a glass dialog still dismisses it', (tester) async {
    final ctx = await _screen(tester);
    showGlassDialog<void>(context: ctx, builder: (_) => const AlertDialog(title: Text('Sure?')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing, reason: 'the backdrop must let taps through to the barrier');
  });

  testWidgets('blurBackdrop: false keeps the tinted dialog and blurs nothing', (tester) async {
    final ctx = await _screen(tester);
    showGlassDialog<void>(context: ctx, blurBackdrop: false, builder: (_) => const AlertDialog(title: Text('Sure?')));
    await tester.pumpAndSettle();
    expect(find.byType(GlassBackdrop), findsNothing);
    expect(_filters(tester), hasLength(1));
  });

  testWidgets('a GlassBackdrop outside any layer is refused', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GlassBackdrop()));
    expect(tester.takeException(), isA<FlutterError>());
  });
}
