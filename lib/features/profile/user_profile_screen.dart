import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/post.dart';
import '../../data/models/user.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/follow_service.dart';
import '../../services/true_fan_profile_service.dart';
import '../../shared/providers/follow_counts_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/follow_button.dart';
import '../../shared/widgets/post_card.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'widgets/true_fan_section.dart';

/// Any user's public profile (`/profile/:userId`) — live header from
/// `users/{userId}`, follow/edit actions, and their posts.
class UserProfileScreen extends ConsumerWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwn = userId == (AuthService.instance.uid ?? '');
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('profile'))),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: StreamBuilder<UserData?>(
          stream: FollowService.instance.watchUser(userId),
          builder: (context, snap) {
            final user = snap.data;
            if (user == null) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.userX, size: 42, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text(ref.tr('userNotFound'), style: AppTextStyles.captionMuted),
                  ],
                ),
              );
            }
            return DefaultTabController(
              length: 3,
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.surface,
                // Streams are live; the gesture is just a familiar affordance.
                onRefresh: () async {
                  Haptics.light();
                  await Future.delayed(const Duration(milliseconds: 400));
                },
                child: NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverToBoxAdapter(child: _Header(user: user, isOwn: isOwn)),
                    SliverToBoxAdapter(
                      child: TabBar(tabs: [
                        Tab(text: ref.tr('posts')),
                        Tab(text: ref.tr('likes')),
                        Tab(text: ref.tr('lists')),
                      ]),
                    ),
                  ],
                  body: TabBarView(
                    children: [
                      _PostsTab(userId: userId),
                      _EmptyTab(text: ref.tr('emptyListTitle')),
                      _EmptyTab(text: ref.tr('emptyListTitle')),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final UserData user;
  final bool isOwn;
  const _Header({required this.user, required this.isOwn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          UserAvatar(name: user.nameToShow, imageUrl: user.userAvatar, radius: 50),
          const SizedBox(height: 10),
          // Nickname is the big name; the unique @handle sits underneath.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(user.nameToShow, style: AppTextStyles.heading, overflow: TextOverflow.ellipsis),
              ),
              if (user.isVerified) ...[
                const SizedBox(width: 6),
                const VerifiedBadge(size: BadgeSize.md),
              ],
            ],
          ),
          if (user.userName.isNotEmpty)
            Text('@${user.userName}', style: AppTextStyles.captionMuted),
          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(user.bio, textAlign: TextAlign.center, style: AppTextStyles.body.copyWith(fontSize: 13.5)),
          ],
          const SizedBox(height: 14),
          _StatsRow(user: user),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isOwn)
                _EditProfileButton(user: user)
              else ...[
                FollowButton(userId: user.id),
                const SizedBox(width: 10),
                _MessageButton(onTap: () {
                  Haptics.light();
                  context.push('/messages');
                }),
              ],
            ],
          ),
          // Public True Fan rail — the owner's hidden titles are filtered
          // out server-side of this widget; nothing renders when empty.
          _TrueFanRail(userId: user.id),
        ],
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

class _StatsRow extends StatelessWidget {
  final UserData user;
  const _StatsRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      // Same relationship-derived source as the own-profile header — the
      // denormalized doc counters are never read for display.
      final counts = ref.watch(followCountsProvider(user.id)).asData?.value;
      String live(int? v) => v == null ? '—' : Fmt.compact(v);
      final items = <(String, String, VoidCallback?)>[
        (live(counts?.followers), ref.tr('followers'),
            () => context.push('/profile/${user.id}/followers')),
        (live(counts?.following), ref.tr('following'),
            () => context.push('/profile/${user.id}/following')),
        (Fmt.compact(user.postsCount), ref.tr('posts'), null),
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
    });
  }
}

class _EditProfileButton extends ConsumerWidget {
  final UserData user;
  const _EditProfileButton({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _editBio(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primaryLight, width: 1.5),
        ),
        child: Text(ref.tr('editProfile'),
            style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ),
    );
  }

  void _editBio(BuildContext context, WidgetRef ref) {
    Haptics.light();
    final ctrl = TextEditingController(text: user.bio);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheetCtx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ref.tr('editProfile'), style: AppTextStyles.subheading),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLength: UserData.maxBioLength,
              maxLines: 3,
              autofocus: true,
              style: AppTextStyles.body,
              decoration: InputDecoration(hintText: ref.tr('notes')),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(sheetCtx), child: Text(ref.tr('cancel'))),
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final failed = ref.tr('actionFailed');
                    final bio = ctrl.text.trim();
                    Navigator.pop(sheetCtx);
                    try {
                      await FollowService.instance.updateBio(bio);
                      ref.read(userProvider.notifier).setBio(bio);
                    } catch (_) {
                      messenger.showSnackBar(SnackBar(content: Text(failed)));
                    }
                  },
                  child: Text(ref.tr('save')),
                ),
              ],
            ),
          ],
        ),
      ),
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

class _PostsTab extends ConsumerWidget {
  final String userId;
  const _PostsTab({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<List<PostData>>(
      stream: FeedService.instance.getUserPosts(userId),
      builder: (context, snap) {
        final posts = snap.data;
        if (posts == null) return const Center(child: CircularProgressIndicator());
        if (posts.isEmpty) return _EmptyTab(text: ref.tr('noPostsYet'));
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          children: posts.map((p) => PostCard(key: ValueKey(p.id), post: p)).toList(),
        );
      },
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final String text;
  const _EmptyTab({required this.text});

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Keeps pull-to-refresh working on an empty tab.
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Center(child: Text(text, textAlign: TextAlign.center, style: AppTextStyles.captionMuted)),
        ),
      ],
    );
  }
}
