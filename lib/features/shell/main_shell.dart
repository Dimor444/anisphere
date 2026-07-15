import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../services/streak_service.dart';
import '../../shared/providers/user_provider.dart';
import '../profile/claim_username_sheet.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/bottom_nav_bar.dart';
import '../../shared/widgets/pressable.dart';
import '../anibot/anibot_sheet.dart';
import '../create/create_screen.dart';

/// Root scaffold for the tabbed app: body + bottom nav + drawer + AniBot FAB.
class MainShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> with WidgetsBindingObserver {
  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Make sure the signed-in user has a public profile doc (`users/{uid}`)
    // so others can follow them and see them in lists/suggestions.
    // Create-only with neutral defaults — never seeds session/sample identity
    // and never overwrites profile edits on restart.
    // Fire-and-forget: the shell must render even if this write fails.
    // The daily streak check-in chains after so the doc exists; checkIn()
    // itself never throws. The @username gate runs last — it needs the doc.
    FollowService.instance
        .ensureProfile()
        .then((_) => StreakService.instance.checkIn())
        .then((_) => _maybePromptUserNameClaim())
        .catchError((Object e) {
      debugPrint('[MainShell] startup profile chain failed: $e');
    });
    // Keep the mirrored isPlus flag current — community-vote rules read it.
    ref.listenManual(userProvider, (prev, next) {
      if (prev?.isPlusUser != next.isPlusUser) {
        FollowService.instance
            .updatePlus(next.isPlusUser)
            .catchError((Object e) => debugPrint('[MainShell] updatePlus failed: $e'));
      }
    });
  }

  /// Backfill gate: accounts without a claimed @handle pick one before
  /// continuing. When even the check can't run (offline / transient), skip
  /// silently — the gate simply re-prompts on the next launch.
  Future<void> _maybePromptUserNameClaim() async {
    bool needs;
    try {
      needs = await FollowService.instance.needsUserNameClaim();
    } catch (e) {
      debugPrint('[MainShell] username gate check skipped: $e');
      return;
    }
    if (!needs || !mounted) return;

    // Default suggestion: sanitized nickname, else the generated handle.
    var suggested = '';
    final uid = AuthService.instance.uid;
    if (uid != null) {
      try {
        final me = await FollowService.instance.getUser(uid);
        suggested = FollowService.suggestHandle(
          me?.displayName ?? '',
          fallback: me?.userName.toLowerCase() ?? '',
        );
      } catch (_) {/* suggestion only — the sheet works from empty */}
    }
    if (!mounted) return;
    await showClaimUserNameSheet(context, suggested: suggested);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A new UTC day can start while backgrounded — check in again on resume.
    // Same-day resumes are a no-op (session memo, no read or write).
    if (state == AppLifecycleState.resumed) StreakService.instance.checkIn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      drawerEdgeDragWidth: 60,
      body: Stack(
        children: [
          navigationShell,
          // AniBot — bottom-left, available on every main screen.
          Positioned(
            left: 14,
            bottom: 14,
            child: Pressable(
              onTap: () => showAniBotSheet(context),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppGradients.brand,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('🤖', style: TextStyle(fontSize: 22)),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: AniBottomNav(
        index: navigationShell.currentIndex,
        onTap: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
        onCreate: () => showCreateSheet(context),
      ),
    );
  }
}
