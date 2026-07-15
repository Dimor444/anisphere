import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/news.dart';
import '../../services/news_service.dart';
import '../../shared/providers/language_provider.dart';

/// Standalone `/news` route.
class NewsScreen extends ConsumerWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('📰 ${ref.tr('news')}')),
      body: const DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.pageBg),
        child: NewsFeed(),
      ),
    );
  }
}

/// The news list itself — embedded both in [NewsScreen] and Discover's News
/// tab. Live category-filtered stream + pull-to-refresh + infinite scroll.
class NewsFeed extends ConsumerStatefulWidget {
  const NewsFeed({super.key});

  @override
  ConsumerState<NewsFeed> createState() => _NewsFeedState();
}

class _NewsFeedState extends ConsumerState<NewsFeed> {
  NewsCategory? _category; // null = All
  late Stream<List<NewsArticle>> _stream = NewsService.instance.getNewsArticles();
  final List<NewsArticle> _older = [];
  bool _loadingMore = false;
  bool _endReached = false;
  DateTime _lastLoadAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  void _select(NewsCategory? category) {
    Haptics.light();
    setState(() {
      _category = category;
      _older.clear();
      _endReached = false;
      _stream = NewsService.instance.getNewsArticles(category: category);
    });
  }

  Future<void> _refresh() async {
    Haptics.light();
    _select(_category);
  }

  Future<void> _loadMore(List<NewsArticle> firstPage) async {
    final now = DateTime.now();
    if (_loadingMore || _endReached || firstPage.isEmpty) return;
    if (now.difference(_lastLoadAttempt).inMilliseconds < 500) return;
    _lastLoadAttempt = now;
    setState(() => _loadingMore = true);
    try {
      final last = _older.isNotEmpty ? _older.last : firstPage.last;
      final more = await NewsService.instance.fetchMoreNews(last, category: _category);
      if (!mounted) return;
      setState(() {
        final seen = {...firstPage.map((a) => a.id), ..._older.map((a) => a.id)};
        _older.addAll(more.where((a) => !seen.contains(a.id)));
        if (more.length < NewsService.pageSize) _endReached = true;
      });
    } catch (_) {
      // Silent — the next scroll retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chips = <(NewsCategory?, String)>[
      (null, ref.tr('all')),
      for (final c in NewsService.instance.getNewsCategories()) (c, ref.tr(c.trKey)),
    ];

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: chips.map((entry) {
              final (cat, label) = entry;
              final sel = cat == _category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: sel,
                  onSelected: (_) => _select(cat),
                  backgroundColor: AppColors.surfaceAlt,
                  selectedColor: cat?.color ?? AppColors.primary,
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                  side: BorderSide(color: sel ? (cat?.color ?? AppColors.primary) : AppColors.border),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: StreamBuilder<List<NewsArticle>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(child: Text(ref.tr('actionFailed'), style: AppTextStyles.captionMuted)),
                    ),
                  ]);
                }
                final articles = snap.data;
                if (articles == null) return const Center(child: CircularProgressIndicator());
                final all = [...articles, ..._older];
                if (all.isEmpty) {
                  return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 60),
                      child: Column(children: [
                        const Icon(LucideIcons.newspaper, size: 42, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        Text(ref.tr('noNewsYet'), style: AppTextStyles.captionMuted),
                      ]),
                    ),
                  ]);
                }
                return NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.axis == Axis.vertical &&
                        n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
                      _loadMore(articles);
                    }
                    return false;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                    itemCount: all.length + (_loadingMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i == all.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                          ),
                        );
                      }
                      return NewsCard(key: ValueKey(all[i].id), article: all[i]);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact article card: image/icon, category badge, title, source · age,
/// description snippet, related-anime chips.
class NewsCard extends StatelessWidget {
  final NewsArticle article;
  const NewsCard({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final a = article;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        context.push('/news/${a.id}', extra: a);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _thumb(a),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CategoryBadge(category: a.category),
                        const SizedBox(height: 6),
                        Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.label),
                        const SizedBox(height: 4),
                        Text(
                          a.publishedAt != null ? '${a.source} · ${Fmt.timeAgo(a.publishedAt!)}' : a.source,
                          style: AppTextStyles.captionMuted,
                        ),
                        if (a.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(a.description,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.captionMuted),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (a.animeIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < a.animeIds.length && i < 5; i++)
                      RelatedAnimeChip(anilistId: a.animeIds[i], title: a.animeTitleAt(i)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumb(NewsArticle a) {
    const radius = BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15));
    if (a.imageUrl != null && a.imageUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: CachedNetworkImage(
          imageUrl: a.imageUrl!,
          width: 90,
          height: 110,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(width: 90, height: 110, color: AppColors.surfaceAlt),
          errorWidget: (_, __, ___) => _iconThumb(a),
        ),
      );
    }
    return _iconThumb(a);
  }

  Widget _iconThumb(NewsArticle a) => Container(
        width: 90,
        height: 110,
        decoration: BoxDecoration(
          gradient: AppGradients.forSeed(a.title),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), bottomLeft: Radius.circular(15)),
        ),
        alignment: Alignment.center,
        child: const Icon(LucideIcons.newspaper, color: Colors.white),
      );
}

class CategoryBadge extends ConsumerWidget {
  final NewsCategory category;
  const CategoryBadge({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: category.color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: category.color.withOpacity(0.5)),
      ),
      child: Text(ref.tr(category.trKey),
          style: AppTextStyles.caption.copyWith(color: category.color, fontWeight: FontWeight.w700)),
    );
  }
}

class RelatedAnimeChip extends StatelessWidget {
  final int anilistId;
  final String title;
  const RelatedAnimeChip({super.key, required this.anilistId, required this.title});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Haptics.light();
        context.push('/trending/anime/$anilistId');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.clapperboard, size: 12, color: AppColors.primaryLight),
            const SizedBox(width: 4),
            Text(title,
                style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
