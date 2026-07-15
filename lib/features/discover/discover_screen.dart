import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/community_vote.dart';
import '../../data/models/user.dart';
import '../../data/sample_data.dart';
import '../../services/chart_service.dart';
import '../../services/community_vote_service.dart';
import '../../services/follow_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_tile.dart';
import '../community_vote/community_vote_screen.dart';
import '../news/news_screen.dart';
import 'search_history.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import '../../services/trending_service.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  static const _searchTabIndex = 7;

  late final TabController _tab = TabController(length: 8, vsync: this);
  final TextEditingController _search = TextEditingController();

  /// Live header-field query — the Search tab listens and debounces.
  final ValueNotifier<String> _query = ValueNotifier('');

  /// Bumped on keyboard submit — a "completed search" signal for history.
  final ValueNotifier<int> _submitTick = ValueNotifier(0);

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    _query.dispose();
    _submitTick.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    setState(() {}); // clear-button visibility
    _query.value = q;
    if (q.trim().length >= 2 && _tab.index != _searchTabIndex) {
      _tab.animateTo(_searchTabIndex);
    }
  }

  void _clear() {
    Haptics.light();
    _search.clear();
    _onQueryChanged('');
  }

  /// Recent/trending chip tap → put the term in the field and search it.
  void _pick(String term) {
    Haptics.light();
    _search.text = term;
    _search.selection = TextSelection.collapsed(offset: term.length);
    _onQueryChanged(term);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.pageBg),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // header + search
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Builder(
                    builder: (ctx) => IconButton(
                      icon: const Icon(LucideIcons.menu),
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('discover-search'),
                      controller: _search,
                      onChanged: _onQueryChanged,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submitTick.value++,
                      decoration: InputDecoration(
                        hintText: ref.tr('searchAnimeHint'),
                        prefixIcon: const Icon(LucideIcons.search, size: 18),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(LucideIcons.x, size: 16),
                                onPressed: _clear,
                              ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'For You'),
                Tab(text: '👥 ${ref.tr('people')}'),
                const Tab(text: 'Trending'),
                const Tab(text: '📰 News'),
                const Tab(text: '💫 AniMatch'),
                const Tab(text: '📊 Chart'),
                Tab(child: _VoteTabLabel(label: ref.tr('vote'))),
                const Tab(text: '🔍 Search'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  const _ForYouTab(),
                  const _PeopleTab(),
                  const _TrendingTab(),
                  const NewsFeed(),
                  const _AniMatchTab(),
                  const _ChartTab(),
                  const CommunityVoteBody(),
                  _SearchTab(query: _query, submits: _submitTick, onPick: _pick),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── For You
class _ForYouTab extends StatelessWidget {
  const _ForYouTab();
  @override
  Widget build(BuildContext context) {
    final friends = SampleData.friends;
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        const SectionHeader(title: 'Because you watched Frieren'),
        _rail(SampleData.animeList.take(6).toList()),
        const SectionHeader(title: 'Friends Are Watching'),
        SizedBox(
          height: 70,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: friends.map((f) {
              return Container(
                width: 220,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    UserAvatar.fromUser(f, radius: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(f.username, style: AppTextStyles.label, overflow: TextOverflow.ellipsis),
                          Text('watching ${f.topAnime.first}', style: AppTextStyles.captionMuted, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.18), AppColors.accent.withOpacity(0.12)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Find Friends With Same Taste 💫', style: AppTextStyles.subheading),
                const SizedBox(height: 6),
                const Text('We found 23 users with 90%+ taste match.', style: AppTextStyles.bodyMuted),
                const SizedBox(height: 12),
                GradientButton(label: 'Open AniMatch', expand: false, onPressed: () {}, gradient: AppGradients.purpleCyan),
              ],
            ),
          ),
        ),
        const _TimeZoneFeed(),
      ],
    );
  }

  Widget _rail(List items) => SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => AnimeCard(anime: items[i]),
        ),
      );
}

class _TimeZoneFeed extends StatefulWidget {
  const _TimeZoneFeed();
  @override
  State<_TimeZoneFeed> createState() => _TimeZoneFeedState();
}

class _TimeZoneFeedState extends State<_TimeZoneFeed> {
  int _i = 0;
  final _zones = ['🇯🇵 Japan', '🇸🇦 Saudi', '🇺🇸 USA', '🇧🇷 Brazil'];
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '🌍 Time Zone Feed'),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: List.generate(_zones.length, (i) {
              final sel = i == _i;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_zones[i]),
                  selected: sel,
                  onSelected: (_) {
                    Haptics.light();
                    setState(() => _i = i);
                  },
                  backgroundColor: AppColors.surfaceAlt,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12),
                  side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
                ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                Text(SampleData.animeList[_i].emoji, style: const TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trending in ${_zones[_i]}', style: AppTextStyles.captionMuted),
                      Text(SampleData.animeList[_i].title, style: AppTextStyles.subheading),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── Trending  (live AniList data)
const _trendingGrid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72);

class _TrendingTab extends StatefulWidget {
  const _TrendingTab();
  @override
  State<_TrendingTab> createState() => _TrendingTabState();
}

class _TrendingTabState extends State<_TrendingTab> {
  late Future<List<TrendingAnime>> _future;

  @override
  void initState() {
    super.initState();
    _future = TrendingService.instance.fetchTrending();
  }

  void _retry() => setState(() => _future = TrendingService.instance.fetchTrending(forceRefresh: true));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrendingAnime>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const _TrendingSkeleton();
        if (snap.hasError) return _TrendingError(onRetry: _retry);
        final items = snap.data ?? const <TrendingAnime>[];
        if (items.isEmpty) return _TrendingError(onRetry: _retry, message: 'No trending anime right now.');
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
          gridDelegate: _trendingGrid,
          itemCount: items.length,
          itemBuilder: (_, i) => _TrendingCard(anime: items[i]),
        );
      },
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final TrendingAnime anime;
  const _TrendingCard({required this.anime});
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {
        Haptics.light();
        // AniList-referenced entry — must go through /trending/anime/:id
        // (fetchById), never /anime/:id which is keyed to sample data.
        context.push('/trending/anime/${anime.id}', extra: anime);
      },
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
              if (anime.score > 0)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 13),
                      const SizedBox(width: 2),
                      Text(anime.score.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
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
                    Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.1)),
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

/// Shimmer placeholder grid shown while the trending list is loading.
class _TrendingSkeleton extends StatelessWidget {
  const _TrendingSkeleton();
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      gridDelegate: _trendingGrid,
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
            const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
            const SizedBox(height: 18),
            GradientButton(label: 'Retry', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── News
class _AniMatchTab extends StatefulWidget {
  const _AniMatchTab();
  @override
  State<_AniMatchTab> createState() => _AniMatchTabState();
}

class _AniMatchTabState extends State<_AniMatchTab> {
  int _filter = 0;
  final _filters = ['80%+', '90%+', '95%+', '🌍 Worldwide'];
  @override
  Widget build(BuildContext context) {
    final threshold = [80, 90, 95, 0][_filter];
    final matches = SampleData.matches.where((m) => m.percent >= threshold).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text('Find Your Anime Soulmate 💫', style: AppTextStyles.heading),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: List.generate(_filters.length, (i) {
              final sel = i == _filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_filters[i]),
                  selected: sel,
                  onSelected: (_) => setState(() => _filter = i),
                  backgroundColor: AppColors.surfaceAlt,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
                ),
              );
            }),
          ),
        ),
        ...matches.map((m) => _MatchCard(match: m)),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  final AniMatch match;
  const _MatchCard({required this.match});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar.fromUser(match.user, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(match.user.username, style: AppTextStyles.subheading),
                      if (match.user.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: BadgeSize.sm)],
                    ]),
                    Text('${match.user.country}  •  ${Fmt.compact(match.user.followers)} followers', style: AppTextStyles.captionMuted),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(gradient: AppGradients.gem, borderRadius: BorderRadius.circular(12)),
                child: Text('🎯 ${match.percent}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: match.shared.map((s) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                  child: Text(s, style: AppTextStyles.caption),
                )).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: GradientButton(label: 'Follow', onPressed: () {}, padding: const EdgeInsets.symmetric(vertical: 10))),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                    child: const Text('Message', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Chart
class _ChartTab extends StatefulWidget {
  const _ChartTab();
  @override
  State<_ChartTab> createState() => _ChartTabState();
}

class _ChartTabState extends State<_ChartTab> {
  ChartFilter _filter = ChartFilter.allTime;

  /// Per-filter results/errors so switching tabs never shows another tab's
  /// state and revisits paint instantly from the service cache.
  final Map<ChartFilter, List<AnimeChartEntry>> _data = {};
  final Map<ChartFilter, bool> _failed = {};
  final Set<ChartFilter> _loading = {};

  @override
  void initState() {
    super.initState();
    _load(_filter);
  }

  Future<void> _load(ChartFilter f) async {
    final cached = ChartService.instance.cached(f);
    if (cached != null) _data[f] = cached; // instant paint, then refresh below
    if (_loading.contains(f)) return;
    _loading.add(f);
    _failed[f] = false;
    if (mounted) setState(() {});
    try {
      final list = await ChartService.instance.getTopAnime(f);
      if (!mounted) return;
      setState(() => _data[f] = list);
    } catch (e) {
      if (!mounted) return;
      // Keep stale data if we have it; only surface the error state bare.
      setState(() => _failed[f] = _data[f] == null);
    } finally {
      _loading.remove(f);
      if (mounted) setState(() {});
    }
  }

  void _select(ChartFilter f) {
    Haptics.light();
    setState(() => _filter = f);
    _load(f);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _data[_filter];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Text('AniSphere Top 100', style: AppTextStyles.heading),
              const Spacer(),
              ...ChartFilter.values.map((f) {
                final sel = f == _filter;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => _select(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: sel ? AppColors.primary : AppColors.border),
                      ),
                      child: Text(f.label, style: TextStyle(fontSize: 11, color: sel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: entries != null
              ? _list(entries)
              : (_failed[_filter] ?? false)
                  ? _error()
                  : _skeleton(),
        ),
      ],
    );
  }

  Widget _list(List<AnimeChartEntry> entries) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = entries[i];
        return GestureDetector(
          onTap: () {
            Haptics.light();
            // Partial extra paints the header instantly; the detail screen
            // fetches the full record (synopsis, genres, status) by id.
            context.push(
              '/trending/anime/${e.anilistId}',
              extra: TrendingAnime(
                id: e.anilistId,
                title: e.title,
                coverUrl: e.coverImage,
                description: '',
                genres: const [],
                status: '',
                score: e.score,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
            child: Row(
              children: [
                SizedBox(width: 30, child: Text('${e.rank}', textAlign: TextAlign.center, style: AppTextStyles.numbersLg())),
                _movement(e.movement),
                const SizedBox(width: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 56,
                    child: e.coverImage.isEmpty
                        ? Container(color: AppColors.surfaceAlt)
                        : CachedNetworkImage(
                            imageUrl: e.coverImage,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                            errorWidget: (_, __, ___) => Container(color: AppColors.surfaceAlt),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title, style: AppTextStyles.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('${Fmt.compact(e.ratings)} ratings', style: AppTextStyles.captionMuted),
                    ],
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 16),
                    const SizedBox(width: 3),
                    Text(e.score.toStringAsFixed(1), style: AppTextStyles.numbers),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _skeleton() {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceAlt,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
        itemCount: 10,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => Container(
          height: 76,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _error() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.cloudOff, size: 42, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Consumer(builder: (context, ref, _) => Text(ref.tr('listError'), style: AppTextStyles.captionMuted)),
          const SizedBox(height: 12),
          Consumer(
            builder: (context, ref, _) => GradientButton(
              label: ref.tr('retry'),
              expand: false,
              onPressed: () => _load(_filter),
            ),
          ),
        ],
      ),
    );
  }

  Widget _movement(int m) {
    if (m == 0) return const Icon(LucideIcons.minus, size: 14, color: AppColors.textMuted);
    final up = m > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 14, color: up ? AppColors.success : AppColors.error),
        Text('${m.abs()}', style: TextStyle(fontSize: 10, color: up ? AppColors.success : AppColors.error, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ───────────────────────── Search
class _SearchTab extends ConsumerStatefulWidget {
  /// Live text of the header search field.
  final ValueListenable<String> query;

  /// Bumped when the user submits from the keyboard — completes the search
  /// for history purposes.
  final ValueListenable<int> submits;

  /// Puts a chip's term back into the header field (and searches it).
  final void Function(String term) onPick;
  const _SearchTab({required this.query, required this.submits, required this.onPick});

  @override
  ConsumerState<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends ConsumerState<_SearchTab> {
  static const _minChars = SearchHistory.minChars;
  static const _debounce = Duration(milliseconds: 450);

  Timer? _timer;
  int _seq = 0; // stale-response guard: only the latest request may land
  List<TrendingAnime>? _results;
  bool _searching = false;
  bool _failed = false;
  List<String> _history = const [];

  String get _q => widget.query.value.trim();

  @override
  void initState() {
    super.initState();
    widget.query.addListener(_onQuery);
    widget.submits.addListener(_onSubmit);
    SearchHistory.load().then((h) {
      if (mounted) setState(() => _history = h);
    });
    if (_q.length >= _minChars) _onQuery();
  }

  @override
  void dispose() {
    widget.query.removeListener(_onQuery);
    widget.submits.removeListener(_onSubmit);
    _timer?.cancel();
    super.dispose();
  }

  /// A search "completed" — result tapped or keyboard submit. This is the
  /// ONLY path into history; the debounced live fetch never writes it.
  Future<void> _commitToHistory(String q) async {
    final updated = await SearchHistory.add(q, _history);
    if (mounted) setState(() => _history = updated);
  }

  void _onSubmit() => _commitToHistory(_q);

  void _onQuery() {
    _timer?.cancel();
    final q = _q;
    if (q.length < _minChars) {
      setState(() {
        _results = null;
        _searching = false;
        _failed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _timer = Timer(_debounce, () => _run(q));
  }

  Future<void> _run(String q) async {
    final seq = ++_seq;
    try {
      final results = await TrendingService.instance.searchAnime(q);
      if (!mounted || seq != _seq) return; // a newer query superseded this one
      setState(() {
        _results = results;
        _searching = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _searching = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_q.length < _minChars) return _defaultView();
    if (_failed) return _message(ref.tr('listError'));
    final results = _results;
    if (results == null || (_searching && results.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.isEmpty) return _message('${ref.tr('noAnimeFound')} "$_q"');
    return _resultsGrid(results);
  }

  Widget _resultsGrid(List<TrendingAnime> results) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.68),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final anime = results[i];
        return _ResultCard(
          anime: anime,
          onTap: () {
            Haptics.light();
            _commitToHistory(_q); // picking a result completes the search
            context.push('/trending/anime/${anime.id}', extra: anime);
          },
        );
      },
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: AppTextStyles.captionMuted),
      ),
    );
  }

  /// Empty-query state: recent searches, trending-search chips, sample grid.
  Widget _defaultView() {
    final tags = ['Frieren', 'Solo Leveling', 'JJK', 'Dandadan', 'AMV', 'Cosplay', 'Theories', 'Tier list'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      children: [
        if (_history.isNotEmpty) ...[
          Text(ref.tr('recentSearches'), style: AppTextStyles.subheading),
          const SizedBox(height: 12),
          _chipWrap(_history, LucideIcons.history, AppColors.textSecondary),
          const SizedBox(height: 24),
        ],
        const Text('Trending searches', style: AppTextStyles.subheading),
        const SizedBox(height: 12),
        _chipWrap(tags, LucideIcons.trendingUp, AppColors.accent),
        const SizedBox(height: 24),
        const Text('Top results', style: AppTextStyles.subheading),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.68),
          itemCount: 9,
          itemBuilder: (_, i) => AnimeCard(anime: SampleData.animeList[i], width: double.infinity, height: double.infinity, showScore: false, showGenre: false),
        ),
      ],
    );
  }

  Widget _chipWrap(List<String> terms, IconData icon, Color iconColor) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: terms
          .map((t) => GestureDetector(
                onTap: () => widget.onPick(t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 13, color: iconColor),
                    const SizedBox(width: 6),
                    Text(t, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
                  ]),
                ),
              ))
          .toList(),
    );
  }
}

/// One search hit: cover + title + year/score. Tap behavior is owned by the
/// search tab (history commit + navigation).
class _ResultCard extends StatelessWidget {
  final TrendingAnime anime;
  final VoidCallback onTap;
  const _ResultCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox.expand(
                child: anime.coverUrl.isEmpty
                    ? DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(anime.title)))
                    : CachedNetworkImage(
                        imageUrl: anime.coverUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                        errorWidget: (_, __, ___) =>
                            DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(anime.title))),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          Row(
            children: [
              if (anime.seasonYear != null)
                Text('${anime.seasonYear}  ', style: AppTextStyles.captionMuted),
              if (anime.score > 0) ...[
                const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 12),
                Text(anime.score.toStringAsFixed(1), style: AppTextStyles.captionMuted),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── People (follow suggestions + user search)
class _PeopleTab extends ConsumerStatefulWidget {
  const _PeopleTab();
  @override
  ConsumerState<_PeopleTab> createState() => _PeopleTabState();
}

class _PeopleTabState extends ConsumerState<_PeopleTab> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<UserData>? _results; // null = not searching (show suggestions)
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await FollowService.instance.searchUsers(q);
        if (!mounted) return;
        setState(() {
          _results = results;
          _searching = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: TextField(
            controller: _query,
            onChanged: _onChanged,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: ref.tr('searchUsers'),
              prefixIcon: const Icon(LucideIcons.search, size: 18),
              isDense: true,
            ),
          ),
        ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _results == null ? _suggestions() : _searchResults(_results!)),
      ],
    );
  }

  Widget _suggestions() {
    return StreamBuilder<List<UserData>>(
      stream: FollowService.instance.getFollowSuggestions(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(ref.tr('actionFailed'), style: AppTextStyles.captionMuted));
        }
        final users = snap.data;
        if (users == null) return const Center(child: CircularProgressIndicator());
        if (users.isEmpty) return _empty(ref.tr('noSuggestions'));
        return ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 90),
          children: [
            SectionHeader(title: '✨ ${ref.tr('suggestedForYou')}'),
            ...users.map((u) => UserTile(
                  key: ValueKey(u.id),
                  user: u,
                  subtitle: '${Fmt.compact(u.followerCount)} ${ref.tr('followers')}',
                )),
          ],
        );
      },
    );
  }

  Widget _searchResults(List<UserData> users) {
    if (users.isEmpty) return _empty(ref.tr('emptyListTitle'));
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      children: users.map((u) => UserTile(
            key: ValueKey(u.id),
            user: u,
            subtitle: '${Fmt.compact(u.followerCount)} ${ref.tr('followers')}',
          )).toList(),
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.usersRound, size: 42, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(text, style: AppTextStyles.captionMuted),
        ],
      ),
    );
  }
}

/// "🗳️ Vote" tab label with a gentle nudge dot while today is unvoted.
class _VoteTabLabel extends StatefulWidget {
  final String label;
  const _VoteTabLabel({required this.label});
  @override
  State<_VoteTabLabel> createState() => _VoteTabLabelState();
}

class _VoteTabLabelState extends State<_VoteTabLabel> {
  // Created once — single-subscription stream must not be rebuilt per frame.
  late final Stream<List<CommunityVote>> _votes =
      CommunityVoteService.instance.getUserVotesToday();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityVote>>(
      stream: _votes,
      builder: (context, snap) {
        final unvoted = (snap.data ?? const []).isEmpty;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🗳️ ${widget.label}'),
            if (unvoted && snap.hasData) ...[
              const SizedBox(width: 5),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
              ),
            ],
          ],
        );
      },
    );
  }
}
