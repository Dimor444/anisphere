import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/post.dart';
import '../../data/sample_data.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../services/my_list_service.dart';
import '../providers/identity_provider.dart';
import '../providers/language_provider.dart';
import 'follow_button.dart';
import 'user_avatar.dart';
import 'verified_badge.dart';

/// One feed post. Renders both Firestore posts and sample/demo posts
/// ([PostData.isLocal]); interactions on local posts stay in-memory.
///
/// Likes are optimistic: the heart fills immediately, the write follows, and
/// a failure reverts the UI with a retry snackbar.
class PostCard extends ConsumerStatefulWidget {
  final PostData post;

  /// Tap-to-expand into the detail screen (off when already on it).
  final bool expandable;
  const PostCard({super.key, required this.post, this.expandable = true});

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _liked = false;
  late int _likes = widget.post.likes;
  bool _likeBusy = false;
  bool _spoilerRevealed = false;

  String get _uid => AuthService.instance.uid ?? '';
  bool get _isOwn => !widget.post.isLocal && widget.post.userId == _uid;

  @override
  void initState() {
    super.initState();
    if (!widget.post.isLocal) _loadInteractionState();
  }

  Future<void> _loadInteractionState() async {
    try {
      final liked = await FeedService.instance.isPostLikedByUser(widget.post.id, _uid);
      if (!mounted) return;
      setState(() => _liked = liked);
    } catch (_) {
      // Leave defaults; the card still renders and like state self-corrects
      // on the next successful toggle.
    }
  }

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    // Real-time counter updates from the stream (unless mid-optimistic-toggle).
    if (old.post.likes != widget.post.likes && !_likeBusy) _likes = widget.post.likes;
  }

  Future<void> _toggleLike() async {
    Haptics.medium();
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += _liked ? 1 : -1;
    });
    if (widget.post.isLocal || _likeBusy) return;

    _likeBusy = true;
    try {
      if (wasLiked) {
        await FeedService.instance.unlikePost(widget.post.id, _uid);
      } else {
        await FeedService.instance.likePost(widget.post.id, _uid);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likes += wasLiked ? 1 : -1;
      });
      _errorSnack(onRetry: _toggleLike);
    } finally {
      _likeBusy = false;
    }
  }

  void _openAuthorProfile() {
    if (widget.post.isLocal) return;
    Haptics.light();
    context.push('/profile/${widget.post.userId}');
  }

  void _errorSnack({required VoidCallback onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ref.tr('actionFailed')),
      action: SnackBarAction(label: ref.tr('retry'), onPressed: onRetry),
    ));
  }

  void _openDetail() {
    if (!widget.expandable || widget.post.isLocal) return;
    Haptics.light();
    context.push('/feed/${widget.post.id}', extra: widget.post);
  }

  void _share() {
    Haptics.light();
    Share.share('${widget.post.userName} on AniSphere:\n\n${widget.post.content}');
  }

  void _showMoreMenu() {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            if (_isOwn)
              ListTile(
                leading: const Icon(LucideIcons.trash2, color: AppColors.secondary, size: 20),
                title: Text(ref.tr('deletePost'), style: AppTextStyles.body.copyWith(color: AppColors.secondary)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDelete();
                },
              )
            else
              ListTile(
                leading: const Icon(LucideIcons.flag, size: 20, color: AppColors.textSecondary),
                title: Text(ref.tr('reportPost'), style: AppTextStyles.body),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  showReportSheet(context, ref, widget.post.id);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(ref.tr('deletePost')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(ref.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(ref.tr('deletePost'), style: const TextStyle(color: AppColors.secondary)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await FeedService.instance.deletePost(widget.post.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('postDeleted'))));
    } catch (_) {
      if (!mounted) return;
      _errorSnack(onRetry: _confirmDelete);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    // Author identity resolves from the live users/{uid} doc; the values
    // denormalized on the post are only the paint-first fallback. Sample
    // posts have no user doc — they keep their local fields.
    final author = p.isLocal ? null : identityOf(ref, p.userId);
    final authorName = author?.nameToShow ?? p.userName;
    final authorVerified = author?.isVerified ?? p.isVerified;
    // Secondary line: "@handle · 2h" once the author resolves, else time only.
    final subLine = [
      if (author != null && author.userName.isNotEmpty) '@${author.userName}',
      if (p.createdAt != null) Fmt.timeAgo(p.createdAt!),
    ].join(' · ');
    return GestureDetector(
      onTap: _openDetail,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  UserAvatar(
                      name: authorName,
                      imageUrl: author?.userAvatar ?? p.userAvatar,
                      radius: 21,
                      onTap: _openAuthorProfile),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openAuthorProfile,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(authorName,
                                    style: AppTextStyles.subheading, overflow: TextOverflow.ellipsis),
                              ),
                              if (authorVerified) ...[
                                const SizedBox(width: 4),
                                const VerifiedBadge(size: BadgeSize.sm),
                              ],
                            ],
                          ),
                          if (subLine.isNotEmpty)
                            Text(subLine,
                                style: AppTextStyles.captionMuted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
                  if (!widget.post.isLocal && !_isOwn) FollowButton(userId: p.userId, compact: true),
                  IconButton(
                    icon: const Icon(LucideIcons.ellipsis, size: 18, color: AppColors.textMuted),
                    visualDensity: VisualDensity.compact,
                    onPressed: p.isLocal ? null : _showMoreMenu,
                  ),
                ],
              ),
            ),

            // ── body text (+spoiler blur) — image-only posts have no caption
            if (p.content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: p.isSpoiler && !_spoilerRevealed
                    ? _SpoilerText(
                        text: p.content,
                        onReveal: () {
                          Haptics.light();
                          setState(() => _spoilerRevealed = true);
                        })
                    : HashtagText(text: p.content),
              ),

            if (p.animeTitle != null && p.animeTitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                child: _AnimeChip(post: p),
              ),

            if (p.imageUrls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: _PostImages(urls: p.imageUrls),
              ),

            // ── reactions
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Row(
                children: [
                  _LikeButton(liked: _liked, count: _likes, onTap: _toggleLike),
                  _ReactionButton(
                    icon: LucideIcons.messageCircle,
                    label: Fmt.compact(p.commentsCount),
                    onTap: _openDetail,
                  ),
                  _ReactionButton(icon: LucideIcons.share2, onTap: _share),
                  const Spacer(),
                  if (p.viewCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.eye, size: 15, color: AppColors.textMuted),
                          const SizedBox(width: 4),
                          Text(Fmt.compact(p.viewCount), style: AppTextStyles.captionMuted),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Report-reason picker; writes to `reports/` on selection.
void showReportSheet(BuildContext context, WidgetRef ref, String postId) {
  final reasons = [
    ('spam', ref.tr('reportSpam')),
    ('spoiler', ref.tr('reportSpoiler')),
    ('abuse', ref.tr('reportAbuse')),
    ('other', ref.tr('reportOther')),
  ];
  final messenger = ScaffoldMessenger.of(context);
  final thanks = ref.tr('postReported');
  final failed = ref.tr('actionFailed');
  showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          Text(ref.tr('whyReport'), style: AppTextStyles.subheading),
          const SizedBox(height: 6),
          for (final (code, label) in reasons)
            ListTile(
              title: Text(label, style: AppTextStyles.body),
              onTap: () async {
                Navigator.pop(sheetCtx);
                try {
                  await FeedService.instance.reportPost(postId, code);
                  messenger.showSnackBar(SnackBar(content: Text(thanks)));
                } catch (_) {
                  messenger.showSnackBar(SnackBar(content: Text(failed)));
                }
              },
            ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

/// Post body with accent-colored, tappable `#hashtags`.
class HashtagText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const HashtagText({super.key, required this.text, this.style});

  @override
  State<HashtagText> createState() => _HashtagTextState();
}

class _HashtagTextState extends State<HashtagText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final base = widget.style ?? AppTextStyles.body;
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in PostData.hashtagPattern.allMatches(widget.text)) {
      if (m.start > cursor) spans.add(TextSpan(text: widget.text.substring(cursor, m.start)));
      final tag = m.group(0)!;
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          Haptics.light();
          context.push('/feed/hashtag/${Uri.encodeComponent(tag.substring(1).toLowerCase())}');
        };
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: tag,
        style: base.copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
        recognizer: recognizer,
      ));
      cursor = m.end;
    }
    if (cursor < widget.text.length) spans.add(TextSpan(text: widget.text.substring(cursor)));

    return Text.rich(TextSpan(style: base, children: spans));
  }
}

class _SpoilerText extends ConsumerWidget {
  final String text;
  final VoidCallback onReveal;
  const _SpoilerText({required this.text, required this.onReveal});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onReveal,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(text, style: AppTextStyles.body),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      AppColors.primary.withOpacity(0.25),
                      AppColors.secondary.withOpacity(0.25),
                    ]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.eyeOff, size: 15, color: AppColors.secondary),
                      const SizedBox(width: 6),
                      Text(ref.tr('spoiler'),
                          style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anime reference chip: cover + title, tap → detail, "+" → Add to My List.
class _AnimeChip extends ConsumerStatefulWidget {
  final PostData post;
  const _AnimeChip({required this.post});

  @override
  ConsumerState<_AnimeChip> createState() => _AnimeChipState();
}

class _AnimeChipState extends ConsumerState<_AnimeChip> {
  bool _adding = false;
  bool _added = false;

  Future<void> _addToList() async {
    final p = widget.post;
    if (p.anilistId == null || _adding || _added) return;
    Haptics.light();
    setState(() => _adding = true);
    try {
      await MyListService.instance
          .addToMyList(p.anilistId!, p.animeTitle ?? '', p.animeCover ?? '', ListStatus.planning);
      if (!mounted) return;
      setState(() => _added = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${p.animeTitle} → ${ref.tr('myList')} ✅')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('listError'))));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _openAnime() {
    final p = widget.post;
    Haptics.light();
    if (p.anilistId != null) {
      context.push('/trending/anime/${p.anilistId}');
    } else {
      context.push('/anime/${SampleData.animeByTitle(p.animeTitle!).id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: GestureDetector(
              onTap: _openAnime,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.animeCover != null && p.animeCover!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(imageUrl: p.animeCover!, width: 20, height: 28, fit: BoxFit.cover),
                    )
                  else
                    const Icon(LucideIcons.hash, size: 13, color: AppColors.primaryLight),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(p.animeTitle!,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          if (p.anilistId != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addToList,
              child: _adding
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_added ? LucideIcons.check : LucideIcons.plus,
                      size: 15, color: _added ? AppColors.success : AppColors.primaryLight),
            ),
          ],
        ],
      ),
    );
  }
}

class _LikeButton extends StatefulWidget {
  final bool liked;
  final int count;
  final VoidCallback onTap;
  const _LikeButton({required this.liked, required this.count, required this.onTap});
  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (!widget.liked) _c.forward(from: 0);
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            ScaleTransition(
              scale: _scale,
              child: Icon(
                widget.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: 20,
                color: widget.liked ? AppColors.secondary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(Fmt.compact(widget.count),
                style: AppTextStyles.caption.copyWith(
                  color: widget.liked ? AppColors.secondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
      ),
    );
  }
}

/// The post's attached images: one image renders full width at its natural
/// aspect (the pre-multi-image look); two or three render as equal square
/// cells in a row. Callers skip this widget entirely for text-only posts.
class _PostImages extends StatelessWidget {
  final List<String> urls;
  const _PostImages({required this.urls});

  Widget _image(String url, {double placeholderAspect = 1}) {
    return CachedNetworkImage(
      imageUrl: url,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => AspectRatio(
        aspectRatio: placeholderAspect,
        child: Container(
          color: AppColors.surfaceAlt,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      errorWidget: (_, __, ___) => AspectRatio(
        aspectRatio: placeholderAspect,
        child: Container(
          color: AppColors.surfaceAlt,
          child: const Icon(LucideIcons.imageOff, color: AppColors.textMuted),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _image(urls.first, placeholderAspect: 16 / 10),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < urls.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 1, child: _image(urls[i])),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  const _ReactionButton({required this.icon, this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    const color = AppColors.textSecondary;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label!, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
