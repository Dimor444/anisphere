import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/post.dart';
import '../../data/sample_data.dart';
import '../../services/feed_service.dart';
import '../../services/follow_service.dart';
import '../stories/stories_row.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/currency_pill.dart';
import '../../shared/widgets/language_sheet.dart';
import '../../shared/widgets/post_card.dart';
import '../../shared/widgets/section_header.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _showTasks = true;

  @override
  void initState() {
    super.initState();
    // Shared, idempotent following watch — feeds the ValueListenableBuilder
    // that drives the following/popular mode switch.
    FollowService.instance.ensureFollowingWatch();
  }


  /// Following mode: real-time first page; older pages accumulate in [_older]
  /// as the user scrolls (fetched once each, no listeners).
  Stream<List<PostData>>? _stream;
  String? _followKey; // sorted following ids — detects set changes
  final List<PostData> _older = [];
  bool _loadingMore = false;
  bool _endReached = false;
  DateTime _lastLoadAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Popular fallback: ranked client-side, so "pagination" just grows the cut.
  Stream<List<PostData>>? _popular;
  int _popularLimit = FeedService.pageSize;

  bool _popularMode = false;

  /// Called from build — assigns stream fields without setState (the caller
  /// is already rebuilding).
  ///
  /// Streams here are single-subscription: after a mode round-trip
  /// (popular → following → popular) a kept instance would already be
  /// consumed and re-listening throws. Every mode transition mints fresh.
  void _syncStreams(List<String> following) {
    final popularMode = following.isEmpty;
    if (popularMode != _popularMode) {
      _popularMode = popularMode;
      if (popularMode) {
        _popular = FeedService.instance.getPopularPosts(limit: _popularLimit);
        _followKey = null; // so returning to following mode resubscribes
        _stream = null;
      }
    }
    if (_popularMode) {
      _popular ??= FeedService.instance.getPopularPosts(limit: _popularLimit);
      return;
    }
    final key = ([...following]..sort()).join(',');
    if (key != _followKey) {
      _followKey = key;
      _older.clear();
      _endReached = false;
      _stream = FeedService.instance.getFeedPosts();
    }
  }

  Future<void> _refresh() async {
    Haptics.light();
    setState(() {
      _older.clear();
      _endReached = false;
      _followKey = null; // forces _syncStreams to resubscribe
      _stream = null;
      _popular = _popularMode ? FeedService.instance.getPopularPosts(limit: _popularLimit) : null;
    });
  }

  /// Debounced (500ms) so scroll notifications don't hammer Firestore.
  Future<void> _loadMore(List<PostData> firstPage) async {
    final now = DateTime.now();
    if (now.difference(_lastLoadAttempt).inMilliseconds < 500) return;
    _lastLoadAttempt = now;

    if (_popularMode) {
      // Ranked list caps at the top 100 of the week.
      if (_popularLimit >= 100 || firstPage.length < _popularLimit) return;
      setState(() {
        _popularLimit += FeedService.pageSize;
        _popular = FeedService.instance.getPopularPosts(limit: _popularLimit);
      });
      return;
    }

    if (_loadingMore || _endReached || firstPage.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final last = _older.isNotEmpty ? _older.last : firstPage.last;
      final more = await FeedService.instance.fetchMorePosts(last);
      if (!mounted) return;
      setState(() {
        final seen = {...firstPage.map((p) => p.id), ..._older.map((p) => p.id)};
        _older.addAll(more.where((p) => !seen.contains(p.id)));
        if (more.length < FeedService.pageSize) _endReached = true;
      });
    } catch (_) {
      // Silent — the footer spinner disappears and the next scroll retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(gradient: AppGradients.pageBg),
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            // Mode switch: empty following → popular fallback; the moment the
            // first follow lands, the following-only feed takes over in place.
            // ValueListenableBuilder (not a stream) — rebuild-safe and shares
            // the service's single Firestore listener.
            child: ValueListenableBuilder<List<String>?>(
              valueListenable: FollowService.instance.followingIdsListenable,
              builder: (context, following, _) {
                if (following != null) _syncStreams(following);
                return StreamBuilder<List<PostData>>(
                  stream: following == null ? null : (_popularMode ? _popular : _stream),
                  builder: (context, snap) {
                    final posts = snap.data;
                    return NotificationListener<ScrollNotification>(
                      onNotification: (n) {
                        if (posts != null &&
                            n.metrics.axis == Axis.vertical &&
                            n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                          _loadMore(posts);
                        }
                        return false;
                      },
                      child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverAppBar(
                        floating: true,
                        snap: true,
                        backgroundColor: AppColors.background.withOpacity(0.9),
                        leading: Builder(
                          builder: (ctx) => IconButton(
                            icon: const Icon(LucideIcons.menu),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                        title: Row(
                          children: [
                            const AniLogo(size: 28),
                            const SizedBox(width: 8),
                            ShaderMask(
                              shaderCallback: (r) => AppGradients.brandTri.createShader(r),
                              child: Text('AniSphere', style: AppTextStyles.wordmark.copyWith(color: Colors.white)),
                            ),
                          ],
                        ),
                        actions: [
                          IconButton(icon: const Icon(LucideIcons.globe, size: 21), onPressed: () => showLanguageSheet(context)),
                          _BellButton(onTap: () => context.push('/notifications')),
                          IconButton(icon: const Icon(LucideIcons.send, size: 21), onPressed: () => context.push('/messages')),
                          const SizedBox(width: 4),
                        ],
                      ),
                      const SliverToBoxAdapter(child: StoriesRow()),
                      const SliverToBoxAdapter(child: CurrencyBar()),
                      if (_showTasks)
                        SliverToBoxAdapter(child: _DailyTasksCard(onDismiss: () => setState(() => _showTasks = false))),
                      ..._postSlivers(snap),
                      const SliverToBoxAdapter(child: SizedBox(height: 90)),
                    ],
                  ),
                );
                  },
                );
              },
            ),
          ),
        ),
        // Compose FAB — bottom-right (AniBot owns bottom-left).
        Positioned(
          right: 14,
          bottom: 14,
          child: GestureDetector(
            onTap: () {
              Haptics.medium();
              context.push('/create-post');
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppGradients.brandTri,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 4)),
                ],
              ),
              child: const Icon(LucideIcons.plus, color: Colors.white, size: 26),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _postSlivers(AsyncSnapshot<List<PostData>> snap) {
    if (snap.hasError) {
      return [SliverToBoxAdapter(child: _FeedMessage(icon: LucideIcons.cloudOff, text: ref.tr('loadFeedError'), retry: _refresh))];
    }
    final posts = snap.data;
    if (posts == null) {
      return const [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator())),
        ),
      ];
    }
    final all = _popularMode ? posts : [...posts, ..._older];
    if (all.isEmpty) {
      return [SliverToBoxAdapter(child: _FeedMessage(icon: LucideIcons.usersRound, text: ref.tr('noPostsYet')))];
    }

    // Interleave a "Trending This Season" rail into the feed.
    final items = <Widget>[];
    if (_popularMode) items.add(const _PopularHeader());
    for (var i = 0; i < all.length; i++) {
      items.add(PostCard(key: ValueKey(all[i].id), post: all[i]));
      if (i == 1) items.add(const _TrendingRail());
    }
    if (all.length < 2) items.add(const _TrendingRail());

    return [
      SliverList(
        delegate: SliverChildListDelegate(
          items.map((w) => w.animate().fadeIn(duration: 250.ms).slideY(begin: 0.06, end: 0)).toList(),
        ),
      ),
      if (_loadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        ),
    ];
  }
}

/// Popular-fallback lead-in: nudge to follow + "Popular This Week" header.
class _PopularHeader extends ConsumerWidget {
  const _PopularHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary.withOpacity(0.18), AppColors.accent.withOpacity(0.12)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.usersRound, size: 26, color: AppColors.primaryLight),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ref.tr('emptyFeedFollow'), style: AppTextStyles.subheading),
                    const SizedBox(height: 2),
                    Text(ref.tr('startFollowingHint'), style: AppTextStyles.captionMuted),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionHeader(title: '🔥 ${ref.tr('popularThisWeek')}'),
      ],
    );
  }
}

class _FeedMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Future<void> Function()? retry;
  const _FeedMessage({required this.icon, required this.text, this.retry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: AppTextStyles.captionMuted.copyWith(fontSize: 14)),
          if (retry != null) ...[
            const SizedBox(height: 12),
            Consumer(
              builder: (context, ref, _) => TextButton(onPressed: retry, child: Text(ref.tr('retry'))),
            ),
          ],
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BellButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(icon: const Icon(LucideIcons.bell, size: 21), onPressed: onTap),
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
            child: const Text('3', style: TextStyle(color: AppColors.onBrand, fontSize: 8, fontWeight: FontWeight.w800, height: 1)),
          ),
        ),
      ],
    );
  }
}

class _DailyTasksCard extends ConsumerWidget {
  final VoidCallback onDismiss;
  const _DailyTasksCard({required this.onDismiss});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = [
      ('Watch an episode', 1.0),
      ('React to 3 posts', 0.66),
      ('Play True Fan', 0.0),
    ];
    return Dismissible(
      key: const ValueKey('daily-tasks'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onDismiss(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.surface, AppColors.surfaceAlt]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('✅', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(ref.tr('dailyTasks'), style: AppTextStyles.subheading),
                const Spacer(),
                const Row(children: [GoldTag(40), SizedBox(width: 2)]),
                const SizedBox(width: 6),
                const Icon(LucideIcons.x, size: 16, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: tasks.map((t) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.$1, maxLines: 2, style: AppTextStyles.caption, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: t.$2,
                            minHeight: 5,
                            backgroundColor: AppColors.background,
                            valueColor: AlwaysStoppedAnimation(t.$2 == 1.0 ? AppColors.success : AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendingRail extends StatelessWidget {
  const _TrendingRail();
  @override
  Widget build(BuildContext context) {
    const titles = SampleData.trendingThisSeason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Consumer(builder: (context, ref, _) => SectionHeader(title: '🔥 ${ref.tr('trendingThisSeason')}')),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: titles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              // map trending label to a known anime for visuals
              final base = SampleData.animeList[i % SampleData.animeList.length];
              return AnimeCard(anime: base, subtitle: titles[i]);
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
