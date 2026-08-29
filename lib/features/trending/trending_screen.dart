import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/my_list_service.dart';
import '../../services/trending_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/pressable.dart';

const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.68);

/// Trending tab — top 10 trending anime, live from AniList.
///
/// Cached data (SharedPreferences, 1-hour TTL) is painted immediately while a
/// fresh fetch runs; pull down to force-refresh.
class TrendingScreen extends ConsumerStatefulWidget {
  const TrendingScreen({super.key});
  @override
  ConsumerState<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends ConsumerState<TrendingScreen> {
  List<TrendingAnime>? _items; // last known data (cache or fresh)
  bool _loading = true; // a fetch is in flight
  Object? _error;
  late final Stream<Map<int, double>> _myScores; // anilist_id → user rating

  @override
  void initState() {
    super.initState();
    _myScores = MyListService.instance.getMyList().map((list) => {
          for (final e in list)
            if (e.score != null) e.anilistId: e.score!,
        });
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // Show cached data instantly while the network fetch runs.
    if (_items == null) {
      final cached = await TrendingService.instance.cached();
      if (mounted && cached != null && cached.isNotEmpty) setState(() => _items = cached);
    }

    try {
      final fresh = await TrendingService.instance.fetchTrending(forceRefresh: force);
      if (mounted) setState(() => _items = fresh);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 16, 4),
                child: Row(
                  children: [
                    // Always reached by push (drawer / My List) — safe to pop.
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      onPressed: () => context.pop(),
                    ),
                    ShaderMask(
                      shaderCallback: (r) => AppGradients.brand.createShader(r),
                      blendMode: BlendMode.srcIn,
                      child: const Icon(LucideIcons.trendingUp, size: 24, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text(ref.tr('trending'), style: AppTextStyles.display.copyWith(fontSize: 24)),
                    const Spacer(),
                    if (_loading && items != null)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Top 10 on AniList right now', style: AppTextStyles.captionMuted),
              ),
              Expanded(child: _body(items)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<TrendingAnime>? items) {
    // Nothing to show yet.
    if (items == null || items.isEmpty) {
      if (_loading) return const _TrendingSkeleton();
      if (_error != null) return _TrendingError(onRetry: () => _load(force: true));
      return _TrendingError(onRetry: () => _load(force: true), message: 'No trending anime right now.');
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      color: AppColors.primaryLight,
      backgroundColor: AppColors.surfaceAlt,
      // My List ratings overlay — degrades to no badges if the stream errors.
      child: StreamBuilder<Map<int, double>>(
        stream: _myScores,
        builder: (context, snap) {
          final scores = snap.data ?? const <int, double>{};
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
            gridDelegate: _grid,
            itemCount: items.length,
            itemBuilder: (_, i) =>
                _TrendingCard(rank: i + 1, anime: items[i], userScore: scores[items[i].id]),
          );
        },
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final int rank;
  final TrendingAnime anime;
  final double? userScore; // the user's own My List rating, if any
  const _TrendingCard({required this.rank, required this.anime, this.userScore});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => context.push('/trending/anime/${anime.id}', extra: anime),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
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
                    colors: [Colors.transparent, Colors.black54, Colors.black87],
                    stops: [0.4, 0.75, 1],
                  ),
                ),
              ),
              // Rank ribbon — brand gradient.
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(8)),
                  child: Text('#$rank', style: TextStyle(color: AppGradients.onFill(AppGradients.brand.colors.first), fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (anime.score > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 13),
                          const SizedBox(width: 2),
                          Text(anime.score.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    if (userScore != null)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(LucideIcons.user, color: AppGradients.onFill(AppGradients.brand.colors.first), size: 11),
                          const SizedBox(width: 2),
                          Text(
                            userScore! == userScore!.roundToDouble()
                                ? '${userScore!.toInt()}'
                                : userScore!.toStringAsFixed(1),
                            style: TextStyle(color: AppGradients.onFill(AppGradients.brand.colors.first), fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ]),
                      ),
                  ],
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
                    Text(anime.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.1)),
                    if (anime.genre.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                          child: Text(anime.genre, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmer placeholder grid shown while the first load is in flight.
class _TrendingSkeleton extends StatelessWidget {
  const _TrendingSkeleton();
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
      gridDelegate: _grid,
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surface,
        highlightColor: AppColors.surfaceAlt,
        child: Container(decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16))),
      ),
    );
  }
}

class _TrendingError extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const _TrendingError({required this.onRetry, this.message = "Couldn't load trending anime.\nCheck your connection and try again."});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.cloudOff, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
            const SizedBox(height: 18),
            Pressable(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCw, size: 16, color: AppGradients.onFill(AppGradients.brand.colors.first)),
                    const SizedBox(width: 8),
                    Text('Retry', style: TextStyle(color: AppGradients.onFill(AppGradients.brand.colors.first), fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
