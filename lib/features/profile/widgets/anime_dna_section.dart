import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_gradients.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/user.dart';
import '../../../services/anime_dna_service.dart';
import '../../../shared/providers/identity_provider.dart';
import '../../feed/create_post_screen.dart' show showAnimePickerSheet;

/// "🧬 Anime DNA" — the profile's real taste fingerprint, derived from
/// `users/{uid}/myList` with owner overrides ([UserData.dnaPinned] /
/// [UserData.firstAnimeId]) resolved live from AniList by id.
///
/// Renders for ANY uid (overrides live on the world-readable user doc; the
/// derived portion degrades gracefully where the target's list isn't
/// client-readable). Editing — pin/unpin and first anime — is own-profile
/// only, via the shared anime picker. Card taps deep-link through the shared
/// AniList detail route (/trending/anime/:id → fetchById), never /anime/:id.
class AnimeDnaSection extends ConsumerStatefulWidget {
  final String uid;
  final bool isOwn;
  const AnimeDnaSection({super.key, required this.uid, required this.isOwn});

  @override
  ConsumerState<AnimeDnaSection> createState() => _AnimeDnaSectionState();
}

class _AnimeDnaSectionState extends ConsumerState<AnimeDnaSection> {
  Future<AnimeDna>? _future;

  /// Fingerprint of the override fields the last fetch used — the identity
  /// stream re-emits on every profile change, and only pin/first-anime
  /// changes should refetch (header rebuilds must not).
  String? _fetchedKey;

  /// A pin/first-anime write is in flight — guards double taps.
  bool _saving = false;

  void _syncFuture(UserData? identity) {
    if (identity == null && _fetchedKey != null) return; // keep last data
    final pinned = identity?.dnaPinned ?? const <int>[];
    final firstAnimeId = identity?.firstAnimeId;
    final key = '${pinned.join(',')}|$firstAnimeId';
    if (key == _fetchedKey) return;
    _fetchedKey = key;
    _future = AnimeDnaService.instance.fetchDna(
      uid: widget.uid,
      pinned: pinned,
      firstAnimeId: firstAnimeId,
    );
  }

  // ── Owner edits ──────────────────────────────────────────────────────────

  Future<void> _save(Future<void> Function() write, String failText) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await write();
      // No refetch here: the users-doc write flows back through
      // identityProvider and _syncFuture picks up the new override key.
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failText), duration: const Duration(seconds: 2)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pinAnime(List<int> current) async {
    Haptics.light();
    final picked = await showAnimePickerSheet(context);
    if (picked == null || picked.anilistId <= 0 || !mounted) return;
    if (current.contains(picked.anilistId)) return;
    await _save(
      () => AnimeDnaService.instance.setPinned([...current, picked.anilistId]),
      "Couldn't pin it — try again.",
    );
  }

  Future<void> _unpin(List<int> current, int anilistId) async {
    Haptics.light();
    await _save(
      () => AnimeDnaService.instance.setPinned(current.where((id) => id != anilistId).toList()),
      "Couldn't unpin it — try again.",
    );
  }

  Future<void> _pickFirstAnime() async {
    Haptics.light();
    final picked = await showAnimePickerSheet(context);
    if (picked == null || picked.anilistId <= 0 || !mounted) return;
    await _save(
      () => AnimeDnaService.instance.setFirstAnime(picked.anilistId),
      "Couldn't save your first anime — try again.",
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final identity = identityOf(ref, widget.uid);
    _syncFuture(identity);
    final future = _future;

    return FutureBuilder<AnimeDna>(
      future: future,
      builder: (context, snap) {
        final dna = snap.data;

        // Visitor surfaces collapse instead of showing errors/empty nudges.
        if (!widget.isOwn) {
          if (future == null || snap.hasError || (dna?.isEmpty ?? false)) {
            return const SizedBox.shrink();
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🧬 Anime DNA', style: AppTextStyles.subheading),
            const SizedBox(height: 10),
            if (future == null || (dna == null && !snap.hasError))
              const _DnaSkeleton()
            else if (snap.hasError)
              const Text("Couldn't load your Anime DNA — pull to refresh or try again later.",
                  style: AppTextStyles.captionMuted)
            else
              ..._loaded(context, dna!, identity),
          ],
        );
      },
    );
  }

  List<Widget> _loaded(BuildContext context, AnimeDna dna, UserData? identity) {
    final pinned = identity?.dnaPinned ?? const <int>[];
    final canPin = widget.isOwn && pinned.length < UserData.maxDnaPinned;
    final showEmptyBox = dna.cards.isEmpty;

    return [
      if (showEmptyBox)
        _emptyCards(context, dna)
      else
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: dna.cards.length + (canPin ? 1 : 0),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => i < dna.cards.length
                ? _DnaCard(
                    card: dna.cards[i],
                    onTap: () {
                      Haptics.light();
                      context.push('/trending/anime/${dna.cards[i].anime.anilistId}');
                    },
                    onUnpin: widget.isOwn && dna.cards[i].pinned
                        ? () => _unpin(pinned, dna.cards[i].anime.anilistId)
                        : null,
                  )
                : _pinCard(pinned),
          ),
        ),
      if (dna.topGenres.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: dna.topGenres
              .map((g) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        gradient: AppGradients.forSeed(g), borderRadius: BorderRadius.circular(20)),
                    child: Text(g,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ))
              .toList(),
        ),
      ],
      ..._firstAnimeLine(dna),
    ];
  }

  /// Own profile with no cards: an inviting nudge, never fake data. (The
  /// visitor variant never reaches here — it collapses on empty DNA.)
  Widget _emptyCards(BuildContext context, AnimeDna dna) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dna.listSize > 0
                ? "Couldn't reach AniList — your DNA will appear once it's back."
                : 'Your Anime DNA grows from your list — add and rate anime to reveal it.',
            style: AppTextStyles.bodyMuted,
          ),
          if (dna.listSize == 0) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                Haptics.light();
                context.push('/my-list');
              },
              child: Text('Open My List →',
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.primaryLight, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  /// Trailing "+ Pin" card (own profile, below the pin cap).
  Widget _pinCard(List<int> pinned) {
    return GestureDetector(
      onTap: _saving ? null : () => _pinAnime(pinned),
      child: Container(
        width: 110,
        height: 150,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.pin, size: 20, color: AppColors.textMuted),
            SizedBox(height: 6),
            Text('Pin anime', style: AppTextStyles.captionMuted),
          ],
        ),
      ),
    );
  }

  List<Widget> _firstAnimeLine(AnimeDna dna) {
    final first = dna.firstAnime;
    if (first != null) {
      final year = first.seasonYear;
      final label = 'First anime: ${first.title}${year != null ? ' ($year)' : ''}';
      if (!widget.isOwn) {
        return [
          const SizedBox(height: 8),
          Text(label, style: AppTextStyles.captionMuted),
        ];
      }
      return [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _saving ? null : _pickFirstAnime,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(label, style: AppTextStyles.captionMuted)),
              const SizedBox(width: 6),
              const Icon(LucideIcons.pencil, size: 12, color: AppColors.textMuted),
            ],
          ),
        ),
      ];
    }
    // Unset: subtle owner affordance; visitors see no line at all.
    if (!widget.isOwn) return const [];
    return [
      const SizedBox(height: 8),
      GestureDetector(
        onTap: _saving ? null : _pickFirstAnime,
        child: Text('🌱 Set your first anime',
            style: AppTextStyles.caption.copyWith(
                color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
      ),
    ];
  }
}

/// Poster card in the Anime DNA rail — matches the AnimeCard/TrueFanCard look
/// (110×150, scrim, score badge top-left, title + genre tag at the bottom).
/// Pinned cards carry a pin badge; [onUnpin] (owner only) makes it tappable.
class _DnaCard extends StatelessWidget {
  final AnimeDnaCard card;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;
  const _DnaCard({required this.card, required this.onTap, this.onUnpin});

  @override
  Widget build(BuildContext context) {
    final anime = card.anime;
    final score = card.displayScore;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 110,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (anime.coverUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: anime.coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _fallback(),
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
              if (score > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 13),
                        const SizedBox(width: 2),
                        Text(score.toStringAsFixed(1),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
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
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.1),
                    ),
                    if (anime.genres.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(anime.genres.first,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
              if (card.pinned)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onUnpin,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.pin, size: 14, color: AppColors.aniGold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        decoration: BoxDecoration(gradient: AppGradients.forSeed(card.anime.title)),
        alignment: Alignment.center,
        child: const Text('🧬', style: TextStyle(fontSize: 34)),
      );
}

/// Shimmer rail with the loaded rail's footprint — never flashes sample data.
class _DnaSkeleton extends StatelessWidget {
  const _DnaSkeleton();
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
