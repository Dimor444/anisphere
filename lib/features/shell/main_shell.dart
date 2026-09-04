import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../../services/streak_service.dart';
import '../profile/claim_username_sheet.dart';
import '../../shared/widgets/app_drawer.dart';
import '../../shared/widgets/bottom_nav_bar.dart';
import '../create/create_screen.dart';

/// Root scaffold for the tabbed app: body + bottom nav + drawer.
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
    // The isPlus mirror is gone: isPlus is server-owned now (firestore.rules
    // forbids the client from writing it), so this listener could only ever
    // fail. Whatever grants AniPlus in future must write users/{uid}.isPlus
    // from a trusted context, not from here.
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
          // The AniBot button stood here, bottom-left on every main screen.
          // Removed because the replies were a hardcoded keyword matcher, and
          // they asserted a taste profile the app had never read — telling a
          // user "based on your taste (Frieren, Vinland Saga, HxH)" when
          // nothing had looked at their list. A confidently wrong assistant is
          // worse than no assistant.
          //
          // lib/features/anibot/ is deliberately KEPT: the sheet, composer and
          // message tree are sound and get reused the moment there is a real
          // recommendations backend reading actual user data. Only the entry
          // point is gone, so restoring it means re-adding a button, not
          // rebuilding a feature. The Stack stays for the same reason.
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
