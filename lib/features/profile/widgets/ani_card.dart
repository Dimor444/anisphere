import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_gradients.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/share_capture.dart';
import '../../../data/models/user.dart';
import '../../../services/my_list_service.dart';
import '../../../shared/providers/identity_provider.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/user_avatar.dart';

/// The AniCard: who the player is and how many anime their My List says they
/// have completed — the profile's card for sharing outside the app.
///
/// Every value is the player's own: identity from their profile, read the way
/// the True Fan card reads it, and the count from their My List. It used to
/// print the sample user's name, avatar, 347 anime, 4,821 episodes, 1,203
/// hours and rank #847 on every profile; those had no source and are gone.
class AniCard extends StatelessWidget {
  /// The signed-in player (users/{uid}); null while that loads, and then the
  /// card prints no one rather than anyone else.
  final UserData? player;

  /// Completed My List entries; null when the count is unknown (still
  /// counting, or the list could not be read).
  final int? completed;

  /// The count is still being read: its stat holds a placeholder.
  final bool completedPending;

  const AniCard({super.key, required this.player, required this.completed, this.completedPending = false});

  @override
  Widget build(BuildContext context) {
    final p = player;
    final flag = p == null ? '' : Fmt.countryFlag(p.countryCode);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('My AniCard', style: AppTextStyles.heading.copyWith(color: Colors.white)),
          if (p != null) ...[
            const SizedBox(height: 16),
            UserAvatar.forIdentity(p, radius: 36),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(p.shownHandle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.display.copyWith(color: Colors.white)),
                ),
                if (flag.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(flag, style: const TextStyle(fontSize: 26)),
                ],
              ],
            ),
          ],
          if (completed != null || completedPending) ...[
            const SizedBox(height: 16),
            Column(children: [
              Text(completed == null ? '…' : Fmt.thousands(completed!),
                  style: AppTextStyles.numbersLg(color: Colors.white)),
              const Text('Completed', style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Opens the AniCard for the signed-in player, with a Share button that
/// sends the card as an image the way the True Fan card does.
Future<void> showAniCardSheet(BuildContext context) {
  Haptics.medium();
  return showModalBottomSheet<void>(
    context: context,
    // Above the bottom bar: shell screens run behind it.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AniCardSheet(),
  );
}

class _AniCardSheet extends ConsumerStatefulWidget {
  const _AniCardSheet();

  @override
  ConsumerState<_AniCardSheet> createState() => _AniCardSheetState();
}

class _AniCardSheetState extends ConsumerState<_AniCardSheet> {
  final _cardKey = GlobalKey();
  int? _completed;
  bool _counting = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _count();
  }

  /// One read of the player's My List, counted once: the card is a snapshot.
  /// A read that fails or stalls leaves no count rather than a guess.
  Future<void> _count() async {
    int? n;
    try {
      final list = await MyListService.instance.getMyList().first.timeout(const Duration(seconds: 8));
      n = list.where((e) => e.status == ListStatus.completed).length;
    } catch (e) {
      debugPrint('[AniCard] no completed count: $e');
    }
    if (mounted) {
      setState(() {
        _completed = n;
        _counting = false;
      });
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await shareBoundaryAsImage(
        boundaryKey: _cardKey,
        fileName: 'anicard.png',
        text: 'My AniCard on AniSphere ✨ #AniSphere',
        origin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (e) {
      debugPrint('[AniCard] share failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t share the card: $e'), duration: const Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = myIdentity(ref);
    // Shared only once it shows the player and the count has settled.
    final ready = player != null && !_counting && !_sharing;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: AniCard(player: player, completed: _completed, completedPending: _counting),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: 'Share AniCard',
            icon: LucideIcons.share2,
            gradient: const LinearGradient(colors: [Colors.white, Color(0xFFE5E7EB)]),
            onPressed: ready ? _share : null,
          ),
        ],
      ),
    );
  }
}
