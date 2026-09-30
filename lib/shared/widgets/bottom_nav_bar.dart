import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/utils/haptics.dart';
import '../providers/language_provider.dart';
import 'glass_surface.dart';

/// Custom 5-slot bottom navigation: Feed | Discover | [+FAB] | Ani Videos | Profile.
/// Trending / My List / Rooms live in the drawer now.
class AniBottomNav extends ConsumerWidget {
  final int index; // 0 feed, 1 discover, 2 ani videos, 3 profile
  final ValueChanged<int> onTap;
  final VoidCallback onCreate;

  const AniBottomNav({
    super.key,
    required this.index,
    required this.onTap,
    required this.onCreate,
  });

  /// Where a shell screen's scroll view should end.
  ///
  /// The shell's body extends behind this bar so the bar can frost what
  /// scrolls under it, and there MediaQuery's bottom padding carries the
  /// bar's full height. A scroll view with a fixed end padding would finish
  /// under the bar; this one ends [gap] above it — 90, what the shell's lists
  /// already ended with, so at rest nothing sits anywhere new. Outside the
  /// shell the same call clears the home indicator instead.
  static double scrollEndPadding(BuildContext context, {double gap = 90}) =>
      MediaQuery.paddingOf(context).bottom + gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Frosted: the body scrolls behind the bar (the shell's extendBody), and
    // the bar is one of the few surfaces in the shell's glass layer.
    return GlassSurface.blur(
      borderRadius: BorderRadius.zero,
      edge: GlassEdge.top,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _item(0, LucideIcons.home, ref.tr('feed')),
              _item(1, LucideIcons.compass, ref.tr('discover')),
              _createFab(),
              _item(2, LucideIcons.playCircle, ref.tr('aniVideos')),
              _item(3, LucideIcons.user, ref.tr('profile')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final active = index == i;
    final icn = Icon(icon, size: 22, color: active ? Colors.white : AppColors.textMuted);
    return Expanded(
      child: InkWell(
        onTap: () {
          Haptics.light();
          onTap(i);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Active icon is painted with the brand gradient; inactive stays muted.
            if (active)
              ShaderMask(
                shaderCallback: (r) => AppGradients.brand.createShader(r),
                blendMode: BlendMode.srcIn,
                child: icn,
              )
            else
              icn,
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.primaryLight : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _createFab() {
    return SizedBox(
      width: 66,
      child: Center(
        child: GestureDetector(
          onTap: () {
            Haptics.medium();
            onCreate();
          },
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: AppGradients.brand,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(LucideIcons.plus, color: Colors.white, size: 26),
          ),
        ),
      ),
    );
  }
}
