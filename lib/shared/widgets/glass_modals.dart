import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import 'glass_surface.dart';

/// The top corners every sheet shares. Call sites used 20, 22 and 24.
const BorderRadius _sheetRadius = BorderRadius.vertical(top: Radius.circular(24));

/// A modal bottom sheet on glass — use this instead of showModalBottomSheet.
///
/// Handles what every call site used to set by hand, differently each time:
/// * the root navigator, so a sheet opened from a shell screen covers the
///   bottom bar instead of opening inside the body that runs behind it;
/// * a clear, flat route Material (no colour, no elevation — a shadow under a
///   translucent fill shows through it as a smudge) and one corner radius;
/// * the glass itself, in its own [GlassLayer]: a sheet floats over the
///   screen's glass, so it cannot share the screen's layer.
///
/// A blurred sheet uses the regular glass fill over a light barrier. Measured
/// on the simulator: with the strong fill over the default dark barrier, a
/// sheet over bright covers read within 2 levels of the same sheet over a
/// plain bar — the barrier halved what was behind, the fill let 12% of that
/// through, and the blur was paid for and invisible. The lighter pair lets
/// the frosted colour through (up to 8 levels) and still reads as modal.
///
/// [blur] false gives the strong fill with no blur — for a sheet over content
/// that moves under it every frame (a playing video), where a blur would be
/// recomputed each frame for nothing and the text needs the denser fill.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool blur = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: blur ? Colors.black26 : Colors.black54,
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: _sheetRadius),
    builder: (_) {
      final content = Builder(builder: builder);
      return blur
          ? GlassLayer(
              child: GlassSurface.blur(borderRadius: _sheetRadius, edge: GlassEdge.top, child: content),
            )
          : GlassSurface.tint(strong: true, borderRadius: _sheetRadius, edge: GlassEdge.top, child: content);
    },
  );
}

/// A dialog over a frosted screen — use this instead of showDialog.
///
/// One blurred surface, not two: the barrier behind the dialog blurs the
/// screen once ([GlassBackdrop], in the route's own [GlassLayer]), and the
/// dialog on top gets the strong fill with no blur of its own — blurring an
/// already-blurred image again would cost a second full pass for nothing.
/// The dialog's look comes from a dialog theme set here, so an AlertDialog
/// that passes its own backgroundColor or shape opts out of it.
///
/// [blurBackdrop] false keeps the glass dialog over a plain dimmed barrier —
/// for a dialog over content that moves every frame (a playing video).
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool blurBackdrop = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    // The route's own SafeArea would inset the backdrop too, leaving the
    // status bar and home-indicator strips unblurred. Only the dialog needs
    // it, so it is applied to the dialog below.
    useSafeArea: false,
    // The blur already separates the dialog from the screen, so the barrier
    // only needs to dim it a little.
    barrierColor: blurBackdrop ? Colors.black26 : Colors.black54,
    builder: (ctx) {
      if (MediaQuery.highContrastOf(ctx)) return SafeArea(child: Builder(builder: builder));
      final theme = Theme.of(ctx);
      final dialog = SafeArea(child: Theme(
        data: theme.copyWith(
          dialogTheme: theme.dialogTheme.copyWith(
            backgroundColor: AppColors.glassFillStrong,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.glassBorder),
            ),
          ),
        ),
        child: Builder(builder: builder),
      ));
      if (!blurBackdrop) return dialog;
      return GlassLayer(
        child: Stack(fit: StackFit.expand, children: [
          // Taps fall through to the route's barrier, so tapping outside
          // still dismisses.
          const IgnorePointer(child: GlassBackdrop()),
          dialog,
        ]),
      );
    },
  );
}
