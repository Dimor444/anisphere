import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_gradients.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/haptics.dart';
import '../../../services/true_fan_profile_service.dart';

/// "🏆 True Fan" — animes with a True Fan pass and their live global ranks,
/// in the Anime DNA section's layout (subheading + 150px horizontal rail).
///
/// Two modes:
///  - OWNER ([onToggleHidden] set): every entry is shown, hidden ones dimmed
///    with a "Hidden" pill, and each card has an eye toggle. Toggles are
///    optimistic — a failed write reverts the card and shows a SnackBar.
///  - VIEWER ([onToggleHidden] null): read-only; callers pass pre-filtered
///    (visible-only) entries and the section collapses when there is nothing
///    to show instead of rendering an empty box.
class TrueFanSection extends StatefulWidget {
  /// Null while ranks are still loading.
  final List<TrueFanProfileEntry>? entries;
  final bool error;

  /// Persists a hide/show change (owner mode). Null renders the read-only
  /// viewer variant.
  final Future<void> Function(int anilistId, bool hidden)? onToggleHidden;

  const TrueFanSection({
    super.key,
    required this.entries,
    required this.error,
    this.onToggleHidden,
  });

  /// Rail shows at most this many; the rest sit behind a "See all" card.
  static const int railCap = 20;

  @override
  State<TrueFanSection> createState() => _TrueFanSectionState();
}

class _TrueFanSectionState extends State<TrueFanSection> {
  /// Optimistic hidden states, keyed by anilistId — override the entry's
  /// stored flag until the parent refetches.
  final Map<int, bool> _overrides = {};

  /// Toggles currently being written, so a card can't be double-tapped.
  final Set<int> _pending = {};

  bool get _isOwner => widget.onToggleHidden != null;

  bool _hiddenOf(TrueFanProfileEntry e) => _overrides[e.anilistId] ?? e.hidden;

  Future<void> _toggle(TrueFanProfileEntry e) async {
    final toggle = widget.onToggleHidden;
    if (toggle == null || _pending.contains(e.anilistId)) return;
    Haptics.light();
    final newHidden = !_hiddenOf(e);
    setState(() {
      _overrides[e.anilistId] = newHidden;
      _pending.add(e.anilistId);
    });
    try {
      await toggle(e.anilistId, newHidden);
    } catch (_) {
      if (!mounted) return;
      // Revert the optimistic flip; the score itself is untouched.
      setState(() => _overrides[e.anilistId] = !newHidden);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newHidden ? "Couldn't hide it — try again." : "Couldn't unhide it — try again."),
        duration: const Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _pending.remove(e.anilistId));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Viewer surfaces collapse instead of showing errors or empty nudges.
    if (!_isOwner && (widget.error || (widget.entries?.isEmpty ?? false))) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🏆 True Fan', style: AppTextStyles.subheading),
        const SizedBox(height: 10),
        _body(context),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (widget.error) {
      return const Text("Couldn't load your True Fan ranks — pull to refresh or try again later.",
          style: AppTextStyles.captionMuted);
    }
    final list = widget.entries;
    if (list == null) return const _TrueFanSkeleton();
    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Text(
          'No True Fan titles yet — beat a challenge to claim your rank.',
          style: AppTextStyles.bodyMuted,
        ),
      );
    }
    final visible = list.length > TrueFanSection.railCap
        ? list.sublist(0, TrueFanSection.railCap)
        : list;
    final overflow = list.length - visible.length;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length + (overflow > 0 ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => i < visible.length
            ? TrueFanCard(
                entry: visible[i],
                hidden: _hiddenOf(visible[i]),
                onToggleHidden: _isOwner ? () => _toggle(visible[i]) : null,
              )
            : _seeAllCard(context, overflow),
      ),
    );
  }

  Widget _seeAllCard(BuildContext context, int overflow) {
    return GestureDetector(
      onTap: () => _showAll(context),
      child: Container(
        width: 110,
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('+$overflow', style: AppTextStyles.numbersLg()),
            const SizedBox(height: 4),
            const Text('See all', style: AppTextStyles.captionMuted),
          ],
        ),
      ),
    );
  }

  void _showAll(BuildContext context) {
    final list = widget.entries;
    if (list == null) return;
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Text('🏆 True Fan titles', style: AppTextStyles.heading),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final e = list[i];
                  final hidden = _isOwner && _hiddenOf(e);
                  return ListTile(
                    dense: true,
                    leading: Text('#${Fmt.thousands(e.rank)}', style: AppTextStyles.numbers),
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hidden)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(LucideIcons.eyeOff, size: 14, color: AppColors.textMuted),
                          ),
                        Text(Fmt.stopwatch((e.timeSeconds * 1000).round()), style: AppTextStyles.captionMuted),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Poster card matching [AnimeCard]'s look (110×150, scrim, bottom title)
/// with the user's global rank badged top-left and their time as subtitle.
/// Owner mode adds an eye toggle; hidden cards dim behind a "Hidden" pill.
class TrueFanCard extends StatelessWidget {
  final TrueFanProfileEntry entry;

  /// Display state (may be an optimistic override of `entry.hidden`).
  final bool hidden;

  /// Owner-only hide/show toggle; null renders no toggle (viewer).
  final VoidCallback? onToggleHidden;

  const TrueFanCard({
    super.key,
    required this.entry,
    this.hidden = false,
    this.onToggleHidden,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Phase-1 card content, dimmed as a whole when hidden.
            Opacity(
              opacity: hidden ? 0.45 : 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Direct AniList cover URL (batch-fetched) — gradient fallback.
                  if (entry.coverUrl.isNotEmpty)
                    Image.network(
                      entry.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _fallback(),
                    )
                  else
                    _fallback(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54, Colors.black87],
                        stops: [0.4, 0.75, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('#${Fmt.thousands(entry.rank)}',
                          style: const TextStyle(color: AppColors.aniGold, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.1),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('⏱ ${Fmt.stopwatch((entry.timeSeconds * 1000).round())}',
                              style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (hidden)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.eyeOff, size: 12, color: Colors.white70),
                      SizedBox(width: 4),
                      Text('Hidden',
                          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            if (onToggleHidden != null)
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleHidden,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      hidden ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        decoration: BoxDecoration(gradient: AppGradients.forSeed(entry.title)),
        alignment: Alignment.center,
        child: const Text('🏆', style: TextStyle(fontSize: 34)),
      );
}

/// Shimmer rail shown while ranks load — same footprint as the loaded rail,
/// so the header never jumps. Never flashes sample data.
class _TrueFanSkeleton extends StatelessWidget {
  const _TrueFanSkeleton();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: AppColors.surface,
          highlightColor: AppColors.surfaceAlt,
          child: Container(
            width: 110,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}
