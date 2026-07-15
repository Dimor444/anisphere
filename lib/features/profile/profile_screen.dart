import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/post.dart';
import '../../data/models/user_model.dart';
import '../../data/models/user_profile.dart';
import '../../data/sample_data.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/profile_repository.dart';
import '../../services/streak_service.dart';
import '../../services/true_fan_profile_service.dart';
import '../../shared/providers/follow_counts_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/anime_cover_image.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/level_badge.dart';
import '../../shared/widgets/post_card.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'edit_profile_sheet.dart';
import 'follow_list_screen.dart';
import 'widgets/true_fan_section.dart';

class ProfileScreen extends ConsumerWidget {
  /// When set, shows this user's profile (e.g. opened from a story/post author)
  /// instead of the signed-in user's; self-only actions are hidden.
  final UserModel? viewUser;
  const ProfileScreen({super.key, this.viewUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserModel user = viewUser ?? ref.watch(userProvider);
    return DefaultTabController(
      length: 6,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 180,
            pinned: false,
            leading: viewUser != null
                ? const BackButton()
                : Builder(
                    builder: (ctx) => IconButton(icon: const Icon(LucideIcons.menu), onPressed: () => Scaffold.of(ctx).openDrawer()),
                  ),
            actions: [
              IconButton(icon: const Icon(LucideIcons.share2, size: 20), onPressed: () => _shareCard(context, user)),
              if (viewUser == null)
                IconButton(icon: const Icon(LucideIcons.settings, size: 20), onPressed: () => context.push('/settings')),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppGradients.brandTri),
                child: Stack(
                  children: [
                    Positioned(right: -20, top: -10, child: Text('∞', style: TextStyle(fontSize: 180, color: Colors.white.withOpacity(0.08)))),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            // Own profile → live Firestore data; profiles opened from
            // stories/posts keep rendering their sample UserModel.
            child: viewUser == null ? _LiveHeader(user: user) : _Header(user: user, isOwn: false),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Posts'), Tab(text: 'Reviews'), Tab(text: 'Lists'),
                  Tab(text: 'Ani Videos'), Tab(text: 'Fan Art'), Tab(text: '📊 Stats'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          children: [
            _PostsTab(),
            const _ReviewsTab(),
            const _ListsTab(),
            const _GridTab(icon: LucideIcons.playCircle, label: 'Ani Video'),
            const _GridTab(icon: LucideIcons.image, label: 'Fan Art'),
            const _StatsTab(),
          ],
        ),
      ),
    );
  }

  void _shareCard(BuildContext context, UserModel u) {
    Haptics.medium();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('My AniCard', style: AppTextStyles.heading.copyWith(color: Colors.white)),
              const SizedBox(height: 16),
              UserAvatar.fromUser(u, radius: 36),
              const SizedBox(height: 10),
              Text(u.username, style: AppTextStyles.display.copyWith(color: Colors.white)),
              Text(u.level.title, style: AppTextStyles.body.copyWith(color: Colors.white70)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _miniStat('${u.watchedAnime}', 'Anime'),
                  _miniStat(Fmt.compact(u.episodes), 'Eps'),
                  _miniStat('${u.hours}h', 'Watched'),
                  _miniStat('#${u.trueFanRank}', 'Rank'),
                ],
              ),
              const SizedBox(height: 18),
              GradientButton(label: 'Share AniCard', icon: LucideIcons.share2, gradient: const LinearGradient(colors: [Colors.white, Color(0xFFE5E7EB)]), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String v, String l) => Column(children: [
        Text(v, style: AppTextStyles.numbersLg(color: Colors.white)),
        Text(l, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ]);
}

/// Header values resolved from Firestore (or placeholders/fallbacks) — the
/// data-only swap for the signed-in user's header. Everything else in the
/// header (level badge, streak, True Fan, Anime DNA) still comes from the
/// session [UserModel] until those features are wired.
class _LiveHeaderData {
  final String displayName;

  /// The unique @handle; '' while loading or before the first claim.
  final String userName;
  final String bio; // empty → bio row hidden
  final String? avatarUrl;
  final String initials;
  final bool isVerified;
  final String animeCount;
  final String followers;
  final String following;
  final String joinDate;

  /// Full text of the streak chip ("🔥 3-day streak" / "🔥 Start your streak").
  final String streakChip;

  /// Full text of the True Fan chip ("🏆 3 True Fan" / "🏆 —" while loading).
  final String trueFanChip;

  /// The user's True Fan passes with live global ranks — null while loading.
  final List<TrueFanProfileEntry>? trueFanEntries;
  final bool trueFanError;

  const _LiveHeaderData({
    required this.displayName,
    required this.userName,
    required this.bio,
    required this.avatarUrl,
    required this.initials,
    required this.isVerified,
    required this.animeCount,
    required this.followers,
    required this.following,
    required this.joinDate,
    required this.streakChip,
    required this.trueFanChip,
    required this.trueFanEntries,
    required this.trueFanError,
  });
}

/// Streams `users/{uid}` and aggregates the counts, then renders the
/// unchanged [_Header] layout with resolved values. Never flashes mock data:
/// stats show "—" while loading and fall back to safe defaults on error.
/// Follow tallies come from [myFollowCountsProvider] so they re-count live
/// after every follow/unfollow instead of once per session.
class _LiveHeader extends ConsumerStatefulWidget {
  final UserModel user;
  const _LiveHeader({required this.user});

  @override
  ConsumerState<_LiveHeader> createState() => _LiveHeaderState();
}

class _LiveHeaderState extends ConsumerState<_LiveHeader> {
  // Held in state so rebuilds don't re-subscribe or refetch.
  late final Stream<UserProfile?> _profile = ProfileRepository.instance.watchProfile();
  late final Future<int> _animeCount = ProfileRepository.instance.fetchMyListCount();
  late final Future<List<TrueFanProfileEntry>> _trueFan =
      TrueFanProfileService.instance.fetchMyEntries();

  @override
  Widget build(BuildContext context) {
    // Relationship-derived counts — re-count on every follow/unfollow.
    final follow = ref.watch(myFollowCountsProvider);
    return StreamBuilder<UserProfile?>(
      stream: _profile,
      builder: (context, profileSnap) => FutureBuilder<int>(
        future: _animeCount,
        builder: (context, animeSnap) => FutureBuilder<List<TrueFanProfileEntry>>(
          future: _trueFan,
          builder: (context, trueFanSnap) => _Header(
              user: widget.user, isOwn: true, live: _resolve(profileSnap, animeSnap, follow, trueFanSnap)),
        ),
      ),
    );
  }

  _LiveHeaderData _resolve(AsyncSnapshot<UserProfile?> p, AsyncSnapshot<int> a,
      AsyncValue<FollowCounts> f, AsyncSnapshot<List<TrueFanProfileEntry>> t) {
    final profile = p.data;
    final profileLoading = p.connectionState == ConnectionState.waiting && !p.hasError;
    final animeLoading = a.connectionState == ConnectionState.waiting && !a.hasError;
    final counts = f.asData?.value;

    // Loading → "—" placeholders; error or missing doc → safe defaults.
    final String displayName;
    final String initials;
    if (profile != null && profile.displayName.isNotEmpty) {
      displayName = profile.displayName;
      initials = profile.initials;
    } else if (profileLoading) {
      displayName = '—';
      initials = '·';
    } else {
      displayName = 'Anime Fan';
      initials = 'AF';
    }

    // Loading → "—" placeholder; error or missing → safe zero.
    String followStat(int? v) => v == null ? (f.isLoading ? '—' : '0') : Fmt.compact(v);

    // Streak chip: placeholder while loading (never flash the sample value),
    // a nudge before the first check-in, then the live count. Display-side
    // only: a lapsed streak (last check-in older than yesterday) shows as 0
    // even though the stored value waits for the next check-in to reset it.
    final String streakChip;
    if (profileLoading) {
      streakChip = '🔥 —';
    } else {
      final streak = profile == null
          ? 0
          : StreakService.displayStreak(
              currentStreak: profile.currentStreak,
              lastActiveDay: profile.lastActiveDay,
            );
      streakChip = streak == 0 ? '🔥 Start your streak' : '🔥 $streak-day streak';
    }

    // True Fan chip shows the COUNT of passed challenges (replaces the old
    // sample "#847" rank). "—" while the ranks load; plain label on error.
    final trueFanEntries = t.data;
    final trueFanError = t.hasError;
    final String trueFanChip;
    if (trueFanEntries != null) {
      trueFanChip = '🏆 ${trueFanEntries.length} True Fan';
    } else {
      trueFanChip = trueFanError ? '🏆 True Fan' : '🏆 —';
    }

    return _LiveHeaderData(
      displayName: displayName,
      userName: profile?.userName ?? '',
      bio: profile?.bio ?? '',
      avatarUrl: profile?.avatarUrl,
      initials: initials,
      isVerified: profile?.isVerified ?? false,
      animeCount: a.data == null ? (animeLoading ? '—' : '0') : '${a.data}',
      followers: followStat(counts?.followers),
      following: followStat(counts?.following),
      joinDate: profileLoading ? '—' : ProfileRepository.instance.joinDate(profile),
      streakChip: streakChip,
      trueFanChip: trueFanChip,
      trueFanEntries: trueFanEntries,
      trueFanError: trueFanError,
    );
  }
}

class _Header extends ConsumerWidget {
  final UserModel user;

  /// True when this is the signed-in user's own profile (stats link to the
  /// real Firestore follower/following lists).
  final bool isOwn;

  /// Live Firestore values for the signed-in user; null → render [user]'s
  /// sample values (profiles opened from stories/posts).
  final _LiveHeaderData? live;
  const _Header({required this.user, this.isOwn = false, this.live});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Data-only swap: live Firestore values when present, sample values
    // otherwise. Layout below is identical either way.
    final l = live;
    final name = l?.displayName ?? user.username;
    // Live profiles show the real claimed handle; sample profiles fake one
    // from the demo username.
    final handle = l?.userName ?? user.username.toLowerCase();
    final bio = l?.bio ?? user.bio;
    final verified = l?.isVerified ?? user.isVerified;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(0, -34),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
                  child: l != null
                      ? UserAvatar(
                          name: l.displayName,
                          level: user.level,
                          imageUrl: l.avatarUrl,
                          initials: l.initials,
                          radius: 38,
                        )
                      : UserAvatar.fromUser(user, radius: 38),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GradientButton(
                    label: ref.tr('editProfile'),
                    expand: false,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    // Editing writes to users/{uid} — own profile only.
                    onPressed: isOwn ? () => showEditProfileSheet(context) : () {},
                  ),
                ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(name, style: AppTextStyles.display.copyWith(fontSize: 22)),
                  const SizedBox(width: 6),
                  if (verified) const VerifiedBadge(size: BadgeSize.md),
                  const SizedBox(width: 8),
                  LevelBadge(level: user.level),
                ]),
                if (handle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('@$handle', style: AppTextStyles.captionMuted),
                ],
                // Empty bio → no row, no gap.
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(bio, style: AppTextStyles.bodyMuted),
                ],
                const SizedBox(height: 14),
                _statsRow(context, user),
                const SizedBox(height: 14),
                _badges(user, verified),
                const SizedBox(height: 16),
                _animeDna(user),
                // Live True Fan ranks exist for the signed-in user only.
                // Owner mode: hidden titles stay visible (dimmed) and each
                // card carries the hide/show eye toggle.
                if (l != null) ...[
                  const SizedBox(height: 16),
                  TrueFanSection(
                    entries: l.trueFanEntries,
                    error: l.trueFanError,
                    onToggleHidden: (anilistId, hidden) => TrueFanProfileService.instance
                        .setHidden(anilistId: anilistId, hidden: hidden),
                  ),
                ],
                const SizedBox(height: 14),
                _banners(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(BuildContext context, UserModel u) {
    // Own profile → the real (Firestore-backed) follower/following lists;
    // sample profiles opened from stories keep the demo list.
    final ownUid = isOwn ? AuthService.instance.uid : null;
    void open(String title) {
      if (ownUid != null) {
        context.push(title == 'Followers' ? '/profile/$ownUid/followers' : '/profile/$ownUid/following');
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FollowListScreen(title: title, users: SampleData.people)),
        );
      }
    }

    final items = <(String, String, VoidCallback?)>[
      (live?.animeCount ?? '${u.watchedAnime}', 'Anime', null),
      (live?.followers ?? Fmt.compact(u.followers), 'Followers', () => open('Followers')),
      (live?.following ?? Fmt.compact(u.following), 'Following', () => open('Following')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Row(
        children: items.map((e) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: e.$3,
            child: Column(children: [
              Text(e.$1, style: AppTextStyles.numbersLg().copyWith(fontSize: 18)),
              const SizedBox(height: 2),
              Text(e.$2, style: AppTextStyles.captionMuted, textAlign: TextAlign.center),
            ]),
          ),
        )).toList(),
      ),
    );
  }

  Widget _badges(UserModel u, bool verified) {
    // Join date, streak, True Fan, and Verified come from live data on the
    // own profile; the birthday chip is a future step and stays as-is.
    final badges = [
      '📅 ${live?.joinDate ?? u.memberSince}', live?.streakChip ?? '🔥 ${u.streak}-day streak', live?.trueFanChip ?? '🌍 True Fan #${u.trueFanRank}', '🎂 Birthday Mar 14', if (verified) '✓ Verified',
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: badges.map((b) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                child: Text(b, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
              ),
            )).toList(),
      ),
    );
  }

  Widget _animeDna(UserModel u) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('🧬 Anime DNA', style: AppTextStyles.subheading),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: u.topAnime.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => AnimeCard(anime: SampleData.animeByTitle(u.topAnime[i]), width: 110, height: 150),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: u.genres.map((g) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(gradient: AppGradients.forSeed(g), borderRadius: BorderRadius.circular(20)),
                child: Text(g, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
              )).toList(),
        ),
        const SizedBox(height: 8),
        Text('First anime: ${u.firstAnime}', style: AppTextStyles.captionMuted),
      ],
    );
  }

  Widget _banners(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: () => context.push('/wrapped'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Text('🎌', style: TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(child: Text('My 2025 Wrapped', style: AppTextStyles.subheading.copyWith(color: Colors.white))),
              const Icon(LucideIcons.chevronRight, color: Colors.white),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _quickBtn(context, '⏰', 'Time Capsule', '/time-capsule')),
            const SizedBox(width: 10),
            Expanded(child: _quickBtn(context, '🎴', 'Card Collection', '/cards')),
          ],
        ),
      ],
    );
  }

  Widget _quickBtn(BuildContext context, String emoji, String label, String route) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: AppTextStyles.label, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: AppColors.background, child: tabBar);
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

class _PostsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The signed-in user's real posts from Firestore — never sample content,
    // so the tab reflects what's actually been published.
    final uid = AuthService.instance.uid;
    if (uid == null) {
      return Center(child: Text(ref.tr('noPostsYet'), style: AppTextStyles.captionMuted));
    }
    return StreamBuilder<List<PostData>>(
      stream: FeedService.instance.getUserPosts(uid),
      builder: (context, snap) {
        final posts = snap.data;
        if (posts == null) return const Center(child: CircularProgressIndicator());
        if (posts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(ref.tr('noPostsYet'), textAlign: TextAlign.center, style: AppTextStyles.captionMuted),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          children: posts.map((p) => PostCard(key: ValueKey(p.id), post: p)).toList(),
        );
      },
    );
  }
}

class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab();
  @override
  Widget build(BuildContext context) {
    final reviews = [
      ('Frieren', 9.5, 'A meditation on time and memory. Peak storytelling.'),
      ('Vinland Saga', 9.0, 'Thorfinn\'s arc from revenge to pacifism is unmatched.'),
      ('Hunter x Hunter', 9.3, 'The Chimera Ant arc rewired my brain.'),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      itemCount: reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final r = reviews[i];
        final a = SampleData.animeByTitle(r.$1);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 60, child: AnimeCoverImage(animeName: a.title, gradient: a.gradient, emoji: a.emoji, emojiSize: 22))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(r.$1, style: AppTextStyles.subheading),
                      const Spacer(),
                      const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 16),
                      Text(' ${r.$2}', style: AppTextStyles.numbers),
                    ]),
                    const SizedBox(height: 4),
                    Text(r.$3, style: AppTextStyles.bodyMuted),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ListsTab extends StatelessWidget {
  const _ListsTab();
  @override
  Widget build(BuildContext context) {
    final lists = [('🏆 All-Time Top 10', 10), ('😭 Made Me Cry', 6), ('⚔️ Best Fights', 14), ('🍂 Cozy Watches', 8)];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      itemCount: lists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Text(lists[i].$1.split(' ').first, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(child: Text(lists[i].$1.substring(lists[i].$1.indexOf(' ') + 1), style: AppTextStyles.subheading)),
          Text('${lists[i].$2} anime', style: AppTextStyles.captionMuted),
          const SizedBox(width: 8),
          const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

class _GridTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _GridTab({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.7),
      itemCount: 9,
      itemBuilder: (_, i) {
        final a = SampleData.animeList[(i + 3) % SampleData.animeList.length];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(fit: StackFit.expand, children: [
            AnimeCoverImage(animeName: a.title, gradient: a.gradient, emoji: a.emoji, emojiSize: 36),
            Positioned(left: 6, bottom: 6, child: Icon(icon, size: 16, color: Colors.white)),
          ]),
        );
      },
    );
  }
}

// ───────────────────────── AniStats
class _StatsTab extends StatelessWidget {
  const _StatsTab();
  @override
  Widget build(BuildContext context) {
    const u = SampleData.mainUser;
    final stats = [
      ('${u.watchedAnime}', 'Anime watched', LucideIcons.tv, AppColors.primary),
      (Fmt.compact(u.episodes), 'Episodes', LucideIcons.playCircle, AppColors.accent),
      ('${u.hours}h', 'Hours watched', LucideIcons.clock, AppColors.secondary),
      ('${(u.hours / 24).round()}d', 'Days of life', LucideIcons.calendar, AppColors.aniGold),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5),
          itemCount: stats.length,
          itemBuilder: (_, i) {
            final s = stats[i];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(s.$3, color: s.$4, size: 22),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.$1, style: AppTextStyles.numbersXl()),
                    Text(s.$2, style: AppTextStyles.captionMuted),
                  ]),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const Text('Genre DNA', style: AppTextStyles.subheading),
        const SizedBox(height: 14),
        SizedBox(height: 180, child: _GenreChart()),
        const SizedBox(height: 20),
        const Text('Watching patterns', style: AppTextStyles.subheading),
        const SizedBox(height: 10),
        ..._patterns().map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(p.$1, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(p.$2, style: AppTextStyles.body)),
              ]),
            )),
        const SizedBox(height: 20),
        const Text('Monthly activity', style: AppTextStyles.subheading),
        const SizedBox(height: 14),
        SizedBox(height: 170, child: _MonthlyChart()),
      ],
    );
  }

  List<(String, String)> _patterns() => [
        ('🌙', 'Night owl — 62% of episodes watched after 10PM'),
        ('🔥', 'Longest binge: 14 episodes of Vinland Saga in a day'),
        ('📅', 'Most active day: Sunday'),
        ('⚡', 'Fastest completion: Chainsaw Man in 2 days'),
      ];
}

class _GenreChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final data = [('Action', 92.0), ('Drama', 78.0), ('Fantasy', 71.0), ('Seinen', 64.0), ('Comedy', 48.0)];
    return BarChart(
      BarChartData(
        maxY: 100,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(data[v.toInt()].$1, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: data[i].$2,
                width: 26,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                gradient: const LinearGradient(colors: [AppColors.secondary, AppColors.primary], begin: Alignment.bottomCenter, end: Alignment.topCenter),
              ),
            ]),
        ],
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    final List<double> vals = [22, 31, 28, 40, 35, 50, 44, 38, 47, 33, 41, 55];
    return BarChart(
      BarChartData(
        maxY: 60,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Text(months[v.toInt()], style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < vals.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: vals[i], width: 12, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)), color: AppColors.accent),
            ]),
        ],
      ),
    );
  }
}
