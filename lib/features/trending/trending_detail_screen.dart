import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/my_list_service.dart';
import '../../services/trending_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/pressable.dart';
import '../my_list/widgets/list_status_ui.dart';

/// Basic detail view for any AniList-referenced anime (read-only).
///
/// The full [AnimeDetailScreen] is keyed to local sample data, so entries
/// referenced by anilist_id only — Trending cards, Top 100 chart rows, deep
/// links — get this lightweight view instead. A router `extra` (even a
/// partial one, e.g. a chart row) paints instantly; missing or partial data
/// is fetched by id from AniList.
class TrendingDetailScreen extends StatefulWidget {
  final int anilistId;
  final TrendingAnime? anime; // passed via router `extra` when available
  const TrendingDetailScreen({super.key, required this.anilistId, this.anime});

  @override
  State<TrendingDetailScreen> createState() => _TrendingDetailScreenState();
}

class _TrendingDetailScreenState extends State<TrendingDetailScreen> {
  TrendingAnime? _anime;
  bool _loading = false;
  bool _expanded = false;

  /// Chart rows pass only id/title/cover/score — synopsis and genres still
  /// need a fetch.
  bool get _isPartial {
    final a = _anime;
    return a != null && a.description.isEmpty && a.genres.isEmpty && a.status.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    _anime = widget.anime;
    if (_anime == null || _isPartial) _resolve();
  }

  /// Fetch the full record by id. With partial data already on screen a
  /// failure stays silent; with nothing on screen it becomes the error state.
  Future<void> _resolve() async {
    setState(() => _loading = true);
    try {
      final full = await TrendingService.instance.fetchById(widget.anilistId);
      if (!mounted) return;
      setState(() => _anime = full ?? _anime);
    } catch (_) {
      // Network failure — keep whatever we have; Retry is offered when empty.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anime = _anime;
    if (anime == null) {
      return _loading ? _loadingScaffold() : _NotFoundScaffold(onRetry: _resolve);
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 320,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: anime.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                      errorWidget: (_, __, ___) => DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(anime.title))),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                          stops: [0.45, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 14,
                      child: Text(anime.title, style: AppTextStyles.display.copyWith(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (anime.status.isNotEmpty) _statusChip(anime.status),
                        if (anime.seasonYear != null) _chip('${anime.seasonYear}', LucideIcons.calendar),
                        for (final g in anime.genres.take(3)) _chip(g, LucideIcons.tag),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (anime.score > 0)
                      Row(children: [
                        const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 28),
                        const SizedBox(width: 4),
                        Text(anime.score.toStringAsFixed(1), style: AppTextStyles.numbersXl()),
                        const SizedBox(width: 6),
                        const Text('/ 10 on AniList', style: AppTextStyles.captionMuted),
                      ]),
                    if (anime.nextAiringAt != null) ...[
                      const SizedBox(height: 14),
                      _nextEpisode(anime),
                    ],
                    const SizedBox(height: 16),
                    _MyListButton(anime: anime),
                    if (anime.description.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('Synopsis', style: AppTextStyles.heading),
                      const SizedBox(height: 8),
                      Text(
                        anime.description,
                        style: AppTextStyles.bodyMuted,
                        maxLines: _expanded ? null : 5,
                        overflow: _expanded ? null : TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Pressable(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_expanded ? 'Less details' : 'More details',
                                style: AppTextStyles.label.copyWith(color: AppColors.primaryLight)),
                            Icon(_expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                size: 16, color: AppColors.primaryLight),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nextEpisode(TrendingAnime anime) {
    final at = anime.nextAiringAt!;
    final when = DateFormat('EEE, MMM d · HH:mm').format(at.toLocal());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            anime.nextEpisode != null ? 'Episode ${anime.nextEpisode} airs $when' : 'Next episode airs $when',
            style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.caption),
      ]),
    );
  }

  Widget _statusChip(String status) {
    final airing = status == 'RELEASING';
    final label = switch (status) {
      'RELEASING' => 'Airing',
      'FINISHED' => 'Finished',
      'NOT_YET_RELEASED' => 'Upcoming',
      'CANCELLED' => 'Cancelled',
      'HIATUS' => 'On hiatus',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: airing ? AppColors.success.withOpacity(0.15) : AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: airing ? AppColors.success : AppColors.border),
      ),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: airing ? AppColors.success : AppColors.textSecondary)),
    );
  }

  Widget _loadingScaffold() {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Add to / Remove from My List, live against Firestore.
class _MyListButton extends ConsumerWidget {
  final TrendingAnime anime;
  const _MyListButton({required this.anime});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {
      if (context.mounted) showMyListError(context, ref, onRetry: () => _run(context, ref, op));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<MyListEntry?>(
      stream: MyListService.instance.watchEntry(anime.id),
      builder: (context, snap) {
        // Auth/permission failure — hide rather than dangle a broken button.
        if (snap.hasError) return const SizedBox.shrink();
        final entry = snap.data;

        if (entry == null) {
          return GradientButton(
            label: ref.tr('addToList'),
            icon: LucideIcons.listPlus,
            onPressed: () async {
              final status = await showStatusPicker(context);
              if (status == null || !context.mounted) return;
              _run(context, ref,
                  () => MyListService.instance.addToMyList(anime.id, anime.title, anime.coverUrl, status));
            },
          );
        }

        return Row(children: [
          Expanded(
            child: Pressable(
              onTap: () => _run(context, ref, () => MyListService.instance.removeFromMyList(anime.id)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.error.withOpacity(0.6)),
                ),
                alignment: Alignment.center,
                child: Text(ref.tr('removeFromList'),
                    style: AppTextStyles.label.copyWith(color: AppColors.error)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          StatusBadge(status: entry.status),
        ]);
      },
    );
  }
}

class _NotFoundScaffold extends ConsumerWidget {
  final VoidCallback onRetry;
  const _NotFoundScaffold({required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load this anime.", style: AppTextStyles.bodyMuted),
            const SizedBox(height: 14),
            GradientButton(label: ref.tr('retry'), expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
