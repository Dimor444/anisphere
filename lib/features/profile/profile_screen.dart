import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliverMainAxisGroup;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/ani_video.dart';
import '../../data/models/post.dart';
import '../../data/models/user.dart';
import '../../data/models/user_model.dart';
import '../../data/sample_data.dart';
import '../../services/ani_video_service.dart';
import '../../services/auth_service.dart';
import '../../services/dm_service.dart';
import '../../services/feed_service.dart';
import '../../services/profile_repository.dart';
import '../../services/streak_service.dart';
import '../../services/true_fan_profile_service.dart';
import '../../shared/providers/follow_counts_provider.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/post_count_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/follow_button.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/level_badge.dart';
import '../../shared/widgets/post_card.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'edit_profile_sheet.dart';
import 'widgets/anime_dna_section.dart';
import 'wrapped_screen.dart';
import 'widgets/ani_card.dart';
import 'widgets/true_fan_section.dart';
import '../../services/currency_service.dart';
import '../../shared/widgets/user_name_text.dart';
import 'card_collection_screen.dart';
import '../../shared/widgets/bottom_nav_bar.dart';
import '../../shared/widgets/glass_app_bar.dart';

// ── Header geometry ────────────────────────────────────────────────────────
// Banner, avatar and action row live in ONE Stack that is sized to contain
// every child. Nothing is translated across sliver boundaries and nothing
// overflows the Stack — a Stack clips AND skips hit-testing outside its
// bounds, so an overflowing child would paint wrong and have dead tap zones.
const double _bannerHeight = 180;
const double _avatarRadius = 44;
const double _ringWidth = 3;

/// Half the avatar (radius + ring) hangs below the banner edge, Instagram-style.
const double _avatarOverlap = _avatarRadius + _ringWidth;

/// Fixed box the action row is centered in. Natural heights (runtime-measured
/// by the phase-3 verification test so a style change can't silently
/// overflow): Edit Profile GradientButton and the Follow + Message row both
/// measure under this.
const double _actionRowHeight = 40;
const double _actionRowTopGap = 8;

/// Breathing room between the avatar's bottom edge and the name column.
const double _bottomGap = 10;

final double _headerStackHeight =
    _bannerHeight + math.max(_avatarOverlap, _actionRowTopGap + _actionRowHeight) + _bottomGap;

/// One profile for everyone. The shell tab (`/profile`) renders it with
/// [userId] null (signed-in user, drawer leading); `/profile/:userId` passes
/// the target uid (back leading). `isOwn` switches actions and own-only
/// sections — the layout is identical either way.
class ProfileScreen extends StatelessWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    final target = userId;
    if (target != null) return _ProfileBody(uid: target, fromTab: false);
    final uid = AuthService.instance.uid;
    if (uid != null) return _ProfileBody(uid: uid, fromTab: true);
    // Tab opened before the guest session resolved — wait for it once.
    return FutureBuilder<User>(
      future: AuthService.instance.initAuth(),
      builder: (context, snap) {
        final user = snap.data;
        if (user != null) return _ProfileBody(uid: user.uid, fromTab: true);
        // Still resolving.
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        // Settled with no user — signed out, or the session could not be
        // established. Terminal either way. This branch is why the test is on
        // connectionState and not on `user == null`: initAuth now REFUSES
        // after a deliberate sign-out, and a refusal leaves data null with
        // hasError set, which the old check read as "still loading" and
        // answered with a spinner that could never stop.
        return const _SignedOutTab();
      },
    );
  }
}

/// The profile tab with nobody signed in. Reuses the userX + existing copy of
/// the not-found state rather than inventing a message: no new string keys,
/// and eight translations stay in step.
class _SignedOutTab extends ConsumerWidget {
  const _SignedOutTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('profile'))),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.userX, size: 42, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(ref.tr('signIn'), style: AppTextStyles.captionMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  final String uid;

  /// True when rendered as the shell tab: drawer leading and no inner
  /// Scaffold (the shell's Scaffold owns the drawer — a nested one would
  /// shadow it and break Scaffold.of(ctx).openDrawer()).
  final bool fromTab;
  const _ProfileBody({required this.uid, required this.fromTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwn = uid == (AuthService.instance.uid ?? '');
    final identityAsync = ref.watch(identityProvider(uid));
    final identity = identityOf(ref, uid);

    // Doc confirmed missing (not merely loading) — visiting semantics only;
    // the own tab renders placeholders while ensureProfile is in flight.
    if (identityAsync is AsyncData<UserData?> && identityAsync.value == null && identity == null && !fromTab) {
      return Scaffold(
        appBar: AppBar(title: Text(ref.tr('profile'))),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppGradients.pageBg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.userX, size: 42, color: AppColors.textMuted),
                const SizedBox(height: 12),
                Text(ref.tr('userNotFound'), style: AppTextStyles.captionMuted),
              ],
            ),
          ),
        ),
      );
    }

    final handle = identity?.userName ?? '';
    // One set of tabs for every profile, own or not, and only tabs with
    // something real behind them: posts and videos, which any signed-in user
    // may read. The controller's length, the bar and the views all come from
    // this list — a length that disagreed with the bar broke this profile
    // before (4af8812). Reviews, Lists, Fan Art and a visitor's Likes are gone:
    // there is no review, custom-list or fan-art feature, My List is readable
    // only by its owner, and likes from builds that predate their uid field
    // cannot be found by user.
    final tabs = <(String, Widget)>[
      (ref.tr('posts'), _PostsTab(userId: uid)),
      (ref.tr('aniVideos'), _VideosTab(userId: uid)),
      if (isOwn && kAniStatsEnabled) ('Stats', const _StatsTab()),
    ];
    final page = DecoratedBox(
      decoration: const BoxDecoration(gradient: AppGradients.pageBg),
      child: DefaultTabController(
        length: tabs.length,
        // No RefreshIndicator: it never armed under the nested scrolling, and
        // with every stream live a refresh had nothing to do.
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            // Both pinned bars cover the top of the tabs once the header has
            // collapsed: absorbed here as one obstruction, injected back as
            // room at the top of every tab (_TabScrollView).
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: _PinnedHeaderGroup(slivers: [
                // Toolbar only — the banner lives in the header Stack below, so
                // no sliver ever paints over the avatar.
                // Pinned: the profile header scrolls up behind it.
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  shape: const Border(),
                  flexibleSpace: const GlassBarBackground(),
                  leading: fromTab
                      ? Builder(
                          builder: (ctx) => IconButton(
                              icon: const Icon(LucideIcons.menu),
                              onPressed: () => Scaffold.of(ctx).openDrawer()),
                        )
                      : const BackButton(),
                  title: handle.isEmpty ? null : Text('@$handle', style: AppTextStyles.subheading),
                  centerTitle: false,
                  actions: [
                    if (isOwn)
                      IconButton(
                          icon: const Icon(LucideIcons.share2, size: 20),
                          onPressed: () => showAniCardSheet(context)),
                    if (isOwn)
                      IconButton(
                          icon: const Icon(LucideIcons.settings, size: 20),
                          onPressed: () => context.push('/settings')),
                  ],
                ),
                SliverToBoxAdapter(child: _ProfileHeader(uid: uid, identity: identity, isOwn: isOwn)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(tabs: [for (final (label, _) in tabs) Tab(text: label)]),
                  ),
                ),
              ]),
            ),
          ],
          body: TabBarView(children: [for (final (_, view) in tabs) view]),
        ),
      ),
    );
    return fromTab ? page : Scaffold(body: page);
  }
}

/// Banner + overlapping avatar + action row (one bounded Stack), then the
/// identity column and stats. Identity resolves via [identityProvider] only.
class _ProfileHeader extends ConsumerWidget {
  final String uid;
  final UserData? identity;
  final bool isOwn;
  const _ProfileHeader({required this.uid, required this.identity, required this.isOwn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = identity?.nameToShow ?? '—';
    final handle = identity?.userName ?? '';
    final bio = identity?.bio ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _headerStackHeight,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: _bannerHeight,
                child: Container(
                  decoration: const BoxDecoration(gradient: AppGradients.brandTri),
                  child: Stack(
                    children: [
                      Positioned(
                          right: -20,
                          top: -10,
                          // Decorative watermark, not readable text — deliberately excluded
                          // from the contrast pass. Do not "fix" to onBrand: at 8% opacity
                          // this is a faint light mark by design; a dark one reads as a smudge.
                          child: Text('∞',
                              style: TextStyle(fontSize: 180, color: Colors.white.withOpacity(0.08)))),
                    ],
                  ),
                ),
              ),
              Positioned(
                // Center of the avatar sits exactly on the banner's bottom edge.
                top: _bannerHeight - _avatarOverlap,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.all(_ringWidth),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.background),
                  child: UserAvatar(
                    name: name == '—' ? '' : name,
                    imageUrl: identity?.userAvatar,
                    frame: identity?.equippedIn(CosmeticSlot.frame),
                    radius: _avatarRadius,
                  ),
                ),
              ),
              Positioned(
                top: _bannerHeight + _actionRowTopGap,
                right: 16,
                child: SizedBox(
                  height: _actionRowHeight,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: isOwn
                          ? [
                              GradientButton(
                                label: ref.tr('editProfile'),
                                expand: false,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                                onPressed: () => showEditProfileSheet(context),
                              ),
                            ]
                          : [
                              FollowButton(userId: uid),
                              const SizedBox(width: 10),
                              _MessageButton(onTap: () async {
                                Haptics.light();
                                // Deterministic cid: same pair, same thread —
                                // safe to call every time.
                                try {
                                  final cid = await DmService.instance
                                      .openConversation(uid);
                                  if (!context.mounted) return;
                                  context.push('/chat/$cid');
                                } on TimeoutException {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            "Can't reach the server — check your connection."),
                                        duration: Duration(seconds: 3)),
                                  );
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text(
                                            "Couldn't open the conversation."),
                                        duration: Duration(seconds: 2)),
                                  );
                                }
                              }),
                            ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: UserNameText(
                    user: identity,
                    fallback: '—',
                    style: AppTextStyles.display.copyWith(fontSize: 22),
                    badgeSize: BadgeSize.md,
                    badgeGap: 6,
                  ),
                ),
                if (isOwn && kUserLevelsEnabled) ...[
                  const SizedBox(width: 8),
                  LevelBadge(level: ref.watch(userProvider).level),
                ],
              ]),
              if (handle.isNotEmpty) ...[
                const SizedBox(height: 2),
                UserHandleText(user: identity, style: AppTextStyles.captionMuted),
              ],
              // Empty bio → no row, no gap.
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(bio, style: AppTextStyles.bodyMuted),
              ],
              const SizedBox(height: 14),
              _StatsRow(uid: uid),
              if (isOwn)
                _OwnSections(uid: uid, identity: identity)
              else ...[
                const SizedBox(height: 14),
                _VisitorChips(identity: identity),
                // Read-only True Fan rail — pads itself when it has content.
                _TrueFanRail(userId: uid),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One stats row for every profile: Posts / Followers / Following — all
/// three relationship-derived ([postCountProvider] / [followCountsProvider]);
/// the denormalized doc counters are never read for display.
class _StatsRow extends ConsumerWidget {
  final String uid;
  const _StatsRow({required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(followCountsProvider(uid)).asData?.value;
    final posts = ref.watch(postCountProvider(uid)).asData?.value;
    String live(int? v) => v == null ? '—' : Fmt.compact(v);
    final items = <(String, String, VoidCallback?)>[
      (live(posts), ref.tr('posts'), null),
      (live(counts?.followers), ref.tr('followers'),
          () => context.push('/profile/$uid/followers')),
      (live(counts?.following), ref.tr('following'),
          () => context.push('/profile/$uid/following')),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: items
            .map((e) => Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: e.$3 == null
                        ? null
                        : () {
                            Haptics.light();
                            e.$3!();
                          },
                    child: Column(children: [
                      Text(e.$1, style: AppTextStyles.numbersLg().copyWith(fontSize: 18)),
                      const SizedBox(height: 2),
                      Text(e.$2, style: AppTextStyles.captionMuted, textAlign: TextAlign.center),
                    ]),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// "March 2024" from the profile's createdAt. Null-tolerant: a pending
/// serverTimestamp surfaces locally as null right after ensureProfile
/// creates the doc (same latency-compensation footgun as Stories).
String _joinDate(DateTime? createdAt) =>
    createdAt == null ? '—' : DateFormat('MMMM yyyy').format(createdAt.toLocal());

Widget _chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border)),
      child: Text(text, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
    );

/// 34px horizontally scrolling chip rail — scrolls, never overflows.
Widget _chipRail(List<String> chips) => SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: chips
            .map((b) => Padding(padding: const EdgeInsets.only(right: 8), child: _chip(b)))
            .toList(),
      ),
    );

/// Public chips every visitor sees: join date + streak. The streak shown is
/// DERIVED from lastActiveDay via [StreakService.displayStreak] — the stored
/// value only refreshes when its owner opens the app — and a broken streak
/// renders no chip at all ("0-day streak" on someone else's profile is
/// owner-directed noise).
class _VisitorChips extends StatelessWidget {
  final UserData? identity;
  const _VisitorChips({required this.identity});

  @override
  Widget build(BuildContext context) {
    final streak = identity == null
        ? 0
        : StreakService.displayStreak(
            currentStreak: identity!.currentStreak,
            lastActiveDay: identity!.lastActiveDay,
          );
    return _chipRail([
      '📅 ${_joinDate(identity?.createdAt)}',
      if (streak > 0) '🔥 $streak-day streak',
    ]);
  }
}

/// Own-profile extras: badges rail, Anime DNA, True Fan section (with the
/// owner's hide/show toggles) and feature banners. Futures held in state so
/// header rebuilds don't refetch.
class _OwnSections extends ConsumerStatefulWidget {
  final String uid;
  final UserData? identity;
  const _OwnSections({required this.uid, required this.identity});

  @override
  ConsumerState<_OwnSections> createState() => _OwnSectionsState();
}

class _OwnSectionsState extends ConsumerState<_OwnSections> {
  late final Future<int> _animeCount = ProfileRepository.instance.fetchMyListCount();
  late final Future<List<TrueFanProfileEntry>> _trueFan =
      TrueFanProfileService.instance.fetchMyEntries();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _animeCount,
      builder: (context, animeSnap) => FutureBuilder<List<TrueFanProfileEntry>>(
        future: _trueFan,
        builder: (context, trueFanSnap) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            _badgesRail(animeSnap, trueFanSnap),
            const SizedBox(height: 16),
            AnimeDnaSection(uid: widget.uid, isOwn: true),
            const SizedBox(height: 16),
            TrueFanSection(
              entries: trueFanSnap.data,
              error: trueFanSnap.hasError,
              onToggleHidden: (anilistId, hidden) =>
                  TrueFanProfileService.instance.setHidden(anilistId: anilistId, hidden: hidden),
            ),
            const SizedBox(height: 14),
            _banners(context),
          ],
        ),
      ),
    );
  }

  Widget _badgesRail(AsyncSnapshot<int> anime, AsyncSnapshot<List<TrueFanProfileEntry>> trueFan) {
    final identity = widget.identity;

    // Placeholder while loading (never flash sample values); a lapsed streak
    // shows as 0 display-side even though the stored value waits for the
    // next check-in to reset it.
    final String streakChip;
    if (identity == null) {
      streakChip = '🔥 —';
    } else {
      final streak = StreakService.displayStreak(
        currentStreak: identity.currentStreak,
        lastActiveDay: identity.lastActiveDay,
      );
      streakChip = streak == 0 ? '🔥 Start your streak' : '🔥 $streak-day streak';
    }

    final String trueFanChip;
    if (trueFan.data != null) {
      trueFanChip = '🏆 ${trueFan.data!.length} True Fan';
    } else {
      trueFanChip = trueFan.hasError ? '🏆 True Fan' : '🏆 —';
    }

    final String animeChip;
    if (anime.data != null) {
      animeChip = '🎌 ${anime.data} anime';
    } else {
      animeChip = anime.hasError ? '🎌 anime' : '🎌 —';
    }

    return _chipRail([
      '📅 ${_joinDate(identity?.createdAt)}',
      streakChip,
      trueFanChip,
      animeChip,
      if (identity?.isVerified ?? false) '✓ Verified',
    ]);
  }

  Widget _banners(BuildContext context) {
    return Column(
      children: [
        // Hidden with the screen it opens; see kWrappedEnabled.
        if (kWrappedEnabled) ...[
          GestureDetector(
            onTap: () => context.push('/wrapped'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Text('🎌', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(child: Text('My 2025 Wrapped', style: AppTextStyles.subheading.copyWith(color: AppGradients.onFill(AppGradients.brandTri.colors.first)))),
                Icon(LucideIcons.chevronRight, color: AppGradients.onFill(AppGradients.brandTri.colors.first)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(child: _quickBtn(context, '⏰', 'Time Capsule', '/time-capsule')),
            if (kCardCollectionEnabled) ...[
              const SizedBox(width: 10),
              Expanded(child: _quickBtn(context, '🎴', 'Card Collection', '/cards')),
            ],
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

/// Read-only True Fan rail for a public profile: only entries the owner
/// hasn't hidden. Collapses entirely (no box, no error) when there's nothing
/// to show; the fetch is held in state so header rebuilds don't refetch.
class _TrueFanRail extends StatefulWidget {
  final String userId;
  const _TrueFanRail({required this.userId});

  @override
  State<_TrueFanRail> createState() => _TrueFanRailState();
}

class _TrueFanRailState extends State<_TrueFanRail> {
  late final Future<List<TrueFanProfileEntry>> _entries =
      TrueFanProfileService.instance.fetchVisibleEntriesFor(widget.userId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TrueFanProfileEntry>>(
      future: _entries,
      builder: (context, snap) {
        // Viewer surface: errors and empty results just collapse.
        if (snap.hasError || (snap.data?.isEmpty ?? false)) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: TrueFanSection(entries: snap.data, error: false),
        );
      },
    );
  }
}

class _MessageButton extends ConsumerWidget {
  final VoidCallback onTap;
  const _MessageButton({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Icon(LucideIcons.send, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(ref.tr('message'),
              style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ]),
      ),
    );
  }
}

/// The profile's header slivers — the pinned app bar, the header that
/// scrolls away under it, the pinned tab bar — as one sliver, so a single
/// SliverOverlapAbsorber can account for both pinned bars. A plain
/// SliverMainAxisGroup sums its pinned children's obstruction while laying
/// them out but reports none, and the absorber reads exactly that figure.
class _PinnedHeaderGroup extends SliverMainAxisGroup {
  const _PinnedHeaderGroup({required super.slivers});

  @override
  RenderSliverMainAxisGroup createRenderObject(BuildContext context) => _RenderPinnedHeaderGroup();
}

class _RenderPinnedHeaderGroup extends RenderSliverMainAxisGroup {
  @override
  void performLayout() {
    super.performLayout();
    final laidOut = geometry!;
    if (laidOut.scrollOffsetCorrection != null) return;
    var obstruction = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      obstruction += child.geometry!.maxScrollObstructionExtent;
    }
    geometry = laidOut.copyWith(maxScrollObstructionExtent: obstruction);
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

  /// Rebuild when the bar itself changed — never merely because the parent
  /// rebuilt.
  ///
  /// This returned a hardcoded `false`, which is wrong for one specific
  /// reason: the profile swaps between a 6-tab bar (own) and a 3-tab bar
  /// (visitor), and `isOwn` is read live from AuthService on every build. When
  /// it flips — signing out is the way to see it — DefaultTabController and
  /// TabBarView drop to 3 while this cached sliver kept painting 6, and the
  /// framework asserts "Controller's length property (3) does not match the
  /// number of tabs (6)".
  ///
  /// Nothing else this delegate renders can change: [minExtent]/[maxExtent]
  /// are the literal 48, and the Container's colour is `AppColors.background`,
  /// a compile-time const. So [tabBar] is the whole dependency, and within it
  /// only the count and the labels are observable — the count catches the
  /// own/visitor swap (which is also the only place isScrollable and
  /// tabAlignment differ), and the labels catch a language change, since the
  /// visitor bar builds its titles through ref.tr.
  ///
  /// Deliberately NOT `true`: that would rebuild the header on every parent
  /// rebuild, and the profile's identity stream emits far more often than the
  /// bar actually changes.
  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
    final before = oldDelegate.tabBar.tabs;
    final after = tabBar.tabs;
    if (before.length != after.length) return true;
    for (var i = 0; i < after.length; i++) {
      if (_labelOf(before[i]) != _labelOf(after[i])) return true;
    }
    return false;
  }

  /// Both profile bars build `Tab(text:)`; anything else compares as null,
  /// which is stable rather than falsely "changed".
  static String? _labelOf(Widget tab) => tab is Tab ? tab.text : null;
}

class _PostsTab extends ConsumerWidget {
  final String userId;
  const _PostsTab({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<PostData>>(
      stream: FeedService.instance.getUserPosts(userId),
      builder: (context, snap) {
        final posts = snap.data;
        if (posts == null) return const _LoadingTab();
        // The profile's own empty state — noPostsYet is the feed's, and tells
        // the reader to follow people.
        if (posts.isEmpty) return _EmptyTab(text: ref.tr('profileNoPosts'));
        return _TabScrollView(slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: 8, bottom: AniBottomNav.scrollEndPadding(context)),
            sliver: SliverList.list(children: [for (final p in posts) PostCard(key: ValueKey(p.id), post: p)]),
          ),
        ]);
      },
    );
  }
}

/// Every tab's scroll view. It starts with the room the pinned app bar and
/// tab bar take once the header has collapsed — absorbed in the header's
/// SliverOverlapAbsorber — so a tab's first row sits below them rather than
/// under them; a tab that scrolls without it hides its newest ~150 points.
/// Content still scrolls behind the glass bar once the tab itself scrolls.
/// Always scrollable, so a short or empty tab still takes a drag.
class _TabScrollView extends StatelessWidget {
  final List<Widget> slivers;
  const _TabScrollView({required this.slivers});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        ...slivers,
      ],
    );
  }
}

class _LoadingTab extends StatelessWidget {
  const _LoadingTab();

  @override
  Widget build(BuildContext context) {
    return const _TabScrollView(slivers: [
      SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
    ]);
  }
}

class _EmptyTab extends StatelessWidget {
  final String text;
  const _EmptyTab({required this.text});

  @override
  Widget build(BuildContext context) {
    return _TabScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(child: Text(text, textAlign: TextAlign.center, style: AppTextStyles.captionMuted)),
        ),
      ),
    ]);
  }
}

/// The player's own videos, newest first, for the author and visitors alike.
/// Thumbnails only: a spoiler shows no picture, the way the feed covers it,
/// and a missing or failed thumbnail shows the play icon. Not tappable — there
/// is no route that plays one video yet, and the grid it replaces was not
/// tappable either.
class _VideosTab extends ConsumerWidget {
  final String userId;
  const _VideosTab({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<AniVideoData>>(
      stream: AniVideoService.instance.watchUserVideos(userId),
      builder: (context, snap) {
        if (snap.hasError) return _EmptyTab(text: ref.tr('videosLoadError'));
        final videos = snap.data;
        if (videos == null) return const _LoadingTab();
        if (videos.isEmpty) return _EmptyTab(text: ref.tr('profileNoVideos'));
        return _TabScrollView(slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, AniBottomNav.scrollEndPadding(context)),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.7),
              itemCount: videos.length,
              itemBuilder: (_, i) => _VideoTile(video: videos[i]),
            ),
          ),
        ]);
      },
    );
  }
}

const _tileShadow = Shadow(color: Colors.black87, blurRadius: 4);

class _VideoTile extends StatelessWidget {
  final AniVideoData video;
  const _VideoTile({required this.video});

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: AppColors.surfaceAlt,
      child: Center(child: Icon(LucideIcons.playCircle, color: AppColors.textMuted, size: 28)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(fit: StackFit.expand, children: [
        if (video.isSpoiler)
          const ColoredBox(
            color: AppColors.surfaceAlt,
            child: Center(child: Icon(LucideIcons.eyeOff, color: AppColors.textMuted, size: 26)),
          )
        else if (video.thumbnailUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: video.thumbnailUrl,
            fit: BoxFit.cover,
            errorListener: (e) => debugPrint('[Profile] video thumbnail ${video.id} failed: $e'),
            errorWidget: (_, __, ___) => fallback,
          )
        else
          fallback,
        Positioned(
          left: 6,
          bottom: 6,
          // Shadowed: the count sits on the thumbnail, which can be bright.
          child: Row(children: [
            const Icon(LucideIcons.play, size: 13, color: Colors.white, shadows: [_tileShadow]),
            const SizedBox(width: 3),
            Text(Fmt.compact(video.viewCount),
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, shadows: [_tileShadow])),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── AniStats

/// Whether the own profile's Stats tab exists.
///
/// Every figure on it was the sample user's, on every account's own profile:
/// 347 anime watched, 4.8K episodes, 1,203 hours, "50d days of life", a fixed
/// genre chart, four watching patterns (a 62% night owl, a 14-episode
/// Vinland Saga binge, Sunday, Chainsaw Man in two days) and twelve fixed
/// monthly bars.
///
/// Almost none of it has a source. My List gives an honest count of anime
/// marked Completed, but not episodes: completing an anime records none of
/// its episodes, so the sum counts only what was stepped by hand. Nothing
/// stores an episode's length, when anything was watched, or which day of
/// the week — so no hours, patterns or monthly activity. Genres can be
/// derived from My List through AniList (one batched query per 50 entries,
/// cached for the session), but the profile's Anime DNA already shows them.
/// What was left — one count the AniCard and My List already show and a
/// repeat of Anime DNA — is not a tab.
///
/// Coming back needs: dated watch activity (when an episode or an anime was
/// finished, written as it happens), episode lengths from AniList for time
/// watched, and a completion step that records episodes. The tab is kept,
/// not deleted.
const bool kAniStatsEnabled = false;

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
    return _TabScrollView(slivers: [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(14, 12, 14, AniBottomNav.scrollEndPadding(context)),
        sliver: SliverList.list(children: [
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
        ]),
      ),
    ]);
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
