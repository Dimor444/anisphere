import 'package:flutter/material.dart';

import 'glass_surface.dart';

/// Frosted glass for a top bar that content scrolls behind — and only for
/// those. A bar with content starting below it sits over the flat page, where
/// a blur shows nothing; those take the theme's glass tint instead.
///
/// Use as a bar's `flexibleSpace`, with the bar's own background transparent,
/// or through [GlassAppBar] for a plain AppBar. The glass reaches up under
/// the status bar, where the content goes too.
///
/// In a collapsing SliverAppBar it stays off while the bar is expanded — the
/// cover image fills the bar and a blur under an opaque picture is paid for
/// and never seen — and comes on for the last toolbar-height of the collapse,
/// exactly where FlexibleSpaceBar fades its image out. [child] (usually that
/// FlexibleSpaceBar) is painted on top.
class GlassBarBackground extends StatelessWidget {
  const GlassBarBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final settings = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final collapsible = settings != null && settings.maxExtent > settings.minExtent;
    final showGlass = !collapsible || settings.currentExtent - settings.minExtent < kToolbarHeight;

    final glass = showGlass
        ? const GlassLayer.ifAbsent(
            child: GlassSurface.blur(
              borderRadius: BorderRadius.zero,
              edge: GlassEdge.bottom,
              child: SizedBox.expand(),
            ),
          )
        : null;
    if (child == null) return glass ?? const SizedBox.shrink();
    return Stack(fit: StackFit.expand, children: [if (glass != null) glass, child!]);
  }
}

/// An AppBar on glass, for a screen whose body scrolls behind the bar
/// (extendBodyBehindAppBar). Everything else is an ordinary AppBar.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({super.key, this.title, this.leading, this.actions, this.bottom});

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) => AppBar(
        title: title,
        leading: leading,
        actions: actions,
        bottom: bottom,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // The glass draws its own bottom edge; the theme's would double it.
        shape: const Border(),
        flexibleSpace: const GlassBarBackground(),
      );
}
