import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/news.dart';
import '../../services/news_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import 'news_screen.dart';

/// Full article (`/news/:newsId`). Bumps the view tally once on open.
class NewsDetailScreen extends ConsumerStatefulWidget {
  final String newsId;

  /// Snapshot from the list so content paints instantly; a one-shot doc read
  /// backfills when deep-linked.
  final NewsArticle? initial;
  const NewsDetailScreen({super.key, required this.newsId, this.initial});

  @override
  ConsumerState<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends ConsumerState<NewsDetailScreen> {
  NewsArticle? _article;
  bool _saveBusy = false;

  @override
  void initState() {
    super.initState();
    _article = widget.initial;
    NewsService.instance.incrementViews(widget.newsId);
    if (_article == null) _load();
  }

  Future<void> _load() async {
    // Deep-link path: articles rarely change after publishing, so a one-shot
    // read (via the search stream's backing query) is enough.
    final all = await NewsService.instance.getNewsArticles(limit: 100).first;
    if (!mounted) return;
    setState(() {
      _article = all.where((a) => a.id == widget.newsId).firstOrNull;
    });
  }

  Future<void> _toggleSave(bool saved) async {
    if (_saveBusy) return;
    Haptics.light();
    _saveBusy = true;
    try {
      if (saved) {
        await NewsService.instance.unsaveArticle(widget.newsId);
      } else {
        await NewsService.instance.saveArticle(widget.newsId);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('actionFailed'))));
      }
    } finally {
      _saveBusy = false;
    }
  }

  Future<void> _openSource(String url) async {
    Haptics.light();
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('actionFailed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _article;
    return Scaffold(
      appBar: AppBar(
        title: Text('📰 ${ref.tr('news')}'),
        actions: [
          if (a != null) ...[
            StreamBuilder<bool>(
              stream: NewsService.instance.watchIsSaved(a.id),
              builder: (context, snap) {
                final saved = snap.data ?? false;
                return IconButton(
                  icon: Icon(saved ? LucideIcons.bookmarkCheck : LucideIcons.bookmark,
                      size: 20, color: saved ? AppColors.primaryLight : null),
                  onPressed: () => _toggleSave(saved),
                );
              },
            ),
            IconButton(
              icon: const Icon(LucideIcons.share2, size: 20),
              onPressed: () {
                Haptics.light();
                Share.share('${a.title}\n\n${a.sourceUrl ?? a.description}');
              },
            ),
          ],
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: a == null ? _missing() : _body(a),
      ),
    );
  }

  Widget _missing() {
    if (widget.initial == null && _article == null) {
      return Center(child: Text(ref.tr('noNewsYet'), style: AppTextStyles.captionMuted));
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _body(NewsArticle a) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        // Header image with a gradient overlay so the badge stays readable.
        if (a.imageUrl != null && a.imageUrl!.isNotEmpty)
          Stack(
            children: [
              CachedNetworkImage(
                imageUrl: a.imageUrl!,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(height: 220, color: AppColors.surfaceAlt),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppColors.background.withOpacity(0.85)],
                    ),
                  ),
                ),
              ),
              Positioned(left: 16, bottom: 12, child: CategoryBadge(category: a.category)),
            ],
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.imageUrl == null || a.imageUrl!.isEmpty) ...[
                CategoryBadge(category: a.category),
                const SizedBox(height: 10),
              ],
              Text(a.title, style: AppTextStyles.heading),
              const SizedBox(height: 6),
              Text(
                a.publishedAt != null ? '${a.source} · ${Fmt.timeAgo(a.publishedAt!)}' : a.source,
                style: AppTextStyles.captionMuted,
              ),
              const SizedBox(height: 14),
              Text(a.description, style: AppTextStyles.body.copyWith(height: 1.5)),
              if (a.animeIds.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(ref.tr('relatedAnime'), style: AppTextStyles.subheading),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < a.animeIds.length; i++)
                      RelatedAnimeChip(anilistId: a.animeIds[i], title: a.animeTitleAt(i)),
                  ],
                ),
              ],
              if (a.sourceUrl != null && a.sourceUrl!.isNotEmpty) ...[
                const SizedBox(height: 22),
                GradientButton(
                  label: ref.tr('readOnSource'),
                  icon: LucideIcons.externalLink,
                  onPressed: () => _openSource(a.sourceUrl!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
