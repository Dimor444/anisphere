import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

/// Which of a glass surface's edges carry the hairline.
enum GlassEdge { all, top, bottom, none }

/// A frosted-glass surface, in one of two modes. The mode is a cost decision
/// made at the call site; the fill and edge are the same either way.
///
/// * [GlassSurface.blur] — a backdrop blur under the fill, grouped with every
///   other blurred surface in its [GlassLayer] so the layer is blurred once.
///   Measured on Impeller: ~2 ms of raster at 40 visible surfaces grouped,
///   against ~12 ms ungrouped. For chrome and modal layers — a handful per
///   screen, over content that moves.
/// * [GlassSurface.tint] — the fill and edge with no blur and no layer.
///   For anything that repeats in a scrolling list, and anything over the
///   flat page background, where a blur is invisible anyway.
///
/// Under High Contrast both modes render the opaque card surface with the
/// solid border, and no blur.
class GlassSurface extends StatelessWidget {
  /// Frosted. Must sit inside a [GlassLayer] — see there for which one.
  const GlassSurface.blur({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = defaultRadius,
    this.edge = GlassEdge.all,
    this.strong = false,
  }) : _mode = _Mode.blur;

  /// Translucent fill, no blur. Needs no layer.
  const GlassSurface.tint({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = defaultRadius,
    this.edge = GlassEdge.all,
    this.strong = false,
  }) : _mode = _Mode.tint;

  /// The one blur strength. Grouped surfaces share a single backdrop read,
  /// so a layer cannot mix strengths — and the cost was measured at this one.
  static const double sigma = 20;

  static const BorderRadius defaultRadius = BorderRadius.all(Radius.circular(16));

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final GlassEdge edge;

  /// The denser fill, for dense text over busy content: sheets, dialogs.
  final bool strong;

  final _Mode _mode;

  Border? _border(Color color) {
    final side = BorderSide(color: color);
    return switch (edge) {
      GlassEdge.all => Border.fromBorderSide(side),
      GlassEdge.top => Border(top: side),
      GlassEdge.bottom => Border(bottom: side),
      GlassEdge.none => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final content = padding == null ? child : Padding(padding: padding!, child: child);

    if (MediaQuery.highContrastOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: borderRadius,
          border: _border(AppColors.border),
        ),
        child: content,
      );
    }

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: strong ? AppColors.glassFillStrong : AppColors.glassFill,
        borderRadius: borderRadius,
        border: _border(AppColors.glassBorder),
      ),
      child: content,
    );
    if (_mode == _Mode.tint) return surface;

    // Clipped, or the filter would reach the whole screen behind it.
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        backdropGroupKey: _GlassLayerScope.keyFor(context),
        child: surface,
      ),
    );
  }
}

enum _Mode { blur, tint }

/// One layer of glass. Every [GlassSurface.blur] below it shares a single
/// backdrop read, so the layer is blurred once however many surfaces it has.
///
/// Surfaces in one layer must not overlap: where two do, only one blur shows.
/// So anything that floats over another glass surface opens a layer of its
/// own — a sheet, a dialog, a menu. The drawer, which is part of the shell but
/// slides over its bottom bar, is cut off from the shell's layer with a
/// [GlassLayerBoundary] and would open its own the same way.
///
/// Opening a layer costs nothing until a blurred surface uses it.
class GlassLayer extends StatefulWidget {
  const GlassLayer({super.key, required this.child});

  final Widget child;

  @override
  State<GlassLayer> createState() => _GlassLayerState();
}

class _GlassLayerState extends State<GlassLayer> {
  // Held in State: a fresh key per build would re-group — and rebuild —
  // every surface in the layer each time the shell rebuilt.
  final BackdropKey _key = BackdropKey();

  @override
  Widget build(BuildContext context) {
    return _GlassLayerScope(
      backdropKey: _key,
      route: ModalRoute.of(context),
      child: widget.child,
    );
  }
}

/// Ends the enclosing [GlassLayer] for its subtree: a blurred surface below it
/// has no layer until one is opened inside. For overlays that live inside a
/// layer's subtree but paint over its glass — the shell's drawer.
class GlassLayerBoundary extends StatelessWidget {
  const GlassLayerBoundary({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _GlassLayerScope(backdropKey: null, route: null, child: child);
}

class _GlassLayerScope extends InheritedWidget {
  const _GlassLayerScope({required this.backdropKey, required this.route, required super.child});

  final BackdropKey? backdropKey;

  /// The route the layer was opened in.
  final ModalRoute<Object?>? route;

  @override
  bool updateShouldNotify(_GlassLayerScope old) =>
      old.backdropKey != backdropKey || old.route != route;

  /// The backdrop key a blurred surface at [context] should use.
  ///
  /// Debug builds refuse the two ways a surface ends up in the wrong layer:
  /// having none at all (it would silently fall back to an ungrouped blur, at
  /// full cost), and sitting in a sheet or dialog — a [PopupRoute] — without a
  /// layer of its own. A sheet opened from a shell screen is pushed on that
  /// screen's navigator, inside the shell's layer; without this check it would
  /// quietly share the shell's blur and overlap its glass. Release builds get
  /// the ungrouped blur instead of an error.
  static BackdropKey? keyFor(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_GlassLayerScope>();
    assert(() {
      if (scope?.backdropKey == null) {
        throw FlutterError(
          'GlassSurface.blur has no GlassLayer.\n'
          'Wrap the layer it belongs to in GlassLayer. Outside one it falls back '
          'to an ungrouped blur, which costs a full blur pass per surface.',
        );
      }
      final route = ModalRoute.of(context);
      if (route is PopupRoute && route != scope!.route) {
        throw FlutterError(
          'GlassSurface.blur is in a sheet or dialog that has no GlassLayer of its own.\n'
          'It would share the layer of the screen underneath and overlap that '
          "screen's glass. Wrap the sheet or dialog content in its own GlassLayer.",
        );
      }
      return true;
    }());
    return scope?.backdropKey;
  }
}
