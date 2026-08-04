import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/ani_video.dart';
import '../../services/ani_video_service.dart';
import '../../services/auth_service.dart';
import '../../services/my_list_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/follow_button.dart';
import '../../shared/widgets/post_card.dart' show HashtagText;
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'ani_video_comments_sheet.dart';

/// Ani Videos — full-screen vertical short-video feed (`/ani-videos` tab).
///
/// One video per page, swipe up/down. `allowImplicitScrolling` keeps exactly
/// the adjacent pages alive, so the next video's controller is already
/// buffering when the user swipes and everything further out is disposed.
class AniVideosScreen extends ConsumerStatefulWidget {
  const AniVideosScreen({super.key});

  @override
  ConsumerState<AniVideosScreen> createState() => _AniVideosScreenState();
}

class _AniVideosScreenState extends ConsumerState<AniVideosScreen> with WidgetsBindingObserver {
  final _page = PageController();
  StreamSubscription<List<AniVideoData>>? _sub;

  List<AniVideoData>? _videos; // null while the first page loads
  Object? _error;
  int _limit = AniVideoService.pageSize;
  int _active = 0;
  bool _appInBackground = false;

  /// Session-wide mute (TikTok-style): flipping it on one page applies to all.
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final background = state != AppLifecycleState.resumed;
    if (background != _appInBackground) setState(() => _appInBackground = background);
  }

  void _listen() {
    _sub?.cancel();
    _sub = AniVideoService.instance.getVideoFeed(limit: _limit).listen((list) {
      final current = (_videos != null && _active < _videos!.length) ? _videos![_active].id : null;
      setState(() {
        _videos = list;
        _error = null;
      });
      if (list.isEmpty) return;
      // A pending server timestamp at the top is our own just-finished upload
      // — surface it. Otherwise keep the user on the video they were watching
      // even when new items shift the indices.
      if (list.first.createdAt == null && list.first.userId == AuthService.instance.uid) {
        _jumpTo(0);
      } else if (current != null) {
        final i = list.indexWhere((v) => v.id == current);
        if (i >= 0 && i != _active) {
          _jumpTo(i);
        } else if (i < 0 && _active >= list.length) {
          _jumpTo(list.length - 1);
        }
      }
    }, onError: (Object e) {
      debugPrint('[AniVideos] feed error: $e');
      setState(() => _error = e);
    });
  }

  void _jumpTo(int i) {
    _active = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _page.hasClients) _page.jumpToPage(i);
    });
  }

  void _onPageChanged(int i) {
    Haptics.light();
    setState(() => _active = i);
    // Near the end with a full page loaded → widen the listener by one page.
    final v = _videos;
    if (v != null && v.length >= _limit && i >= v.length - 2) {
      _limit += AniVideoService.pageSize;
      _listen();
    }
  }

  void _refresh() {
    Haptics.light();
    _limit = AniVideoService.pageSize;
    if (_page.hasClients && (_videos?.isNotEmpty ?? false)) _page.jumpToPage(0);
    _active = 0;
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final videos = _videos;

    Widget body;
    if (_error != null && (videos == null || videos.isEmpty)) {
      body = _Message(
        icon: LucideIcons.wifiOff,
        text: ref.tr('videosLoadError'),
        actionLabel: ref.tr('retry'),
        onAction: _refresh,
      );
    } else if (videos == null) {
      body = const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2));
    } else if (videos.isEmpty) {
      body = _Message(
        icon: LucideIcons.clapperboard,
        text: ref.tr('noVideosYet'),
        actionLabel: ref.tr('uploadVideo'),
        onAction: () => context.push('/ani-videos/upload'),
      );
    } else {
      body = PageView.builder(
        controller: _page,
        scrollDirection: Axis.vertical,
        allowImplicitScrolling: true, // pre-builds (and pre-buffers) the next page
        onPageChanged: _onPageChanged,
        itemCount: videos.length,
        itemBuilder: (_, i) => _VideoPage(
          key: ValueKey(videos[i].id),
          video: videos[i],
          isActive: i == _active && !_appInBackground,
          muted: _muted,
          onToggleMute: () => setState(() => _muted = !_muted),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          // Slim top bar: title + refresh + upload, over the video.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text('🎬 ${ref.tr('aniVideos')}',
                          style: AppTextStyles.subheading.copyWith(color: Colors.white)),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _refresh,
                      icon: const Icon(LucideIcons.refreshCw, color: Colors.white, size: 20),
                    ),
                    IconButton(
                      onPressed: () {
                        Haptics.medium();
                        context.push('/ani-videos/upload');
                      },
                      icon: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          gradient: AppGradients.brand,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(LucideIcons.plus, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  const _Message({required this.icon, required this.text, required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white38, size: 44),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: AppTextStyles.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.primary),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// One full-screen video page: player + progress bar + action rail + overlay.
class _VideoPage extends ConsumerStatefulWidget {
  final AniVideoData video;
  final bool isActive;
  final bool muted;
  final VoidCallback onToggleMute;
  const _VideoPage({
    super.key,
    required this.video,
    required this.isActive,
    required this.muted,
    required this.onToggleMute,
  });

  @override
  ConsumerState<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends ConsumerState<_VideoPage> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _userPaused = false;
  bool _spoilerRevealed = false;

  bool _liked = false;
  late int _likes = widget.video.likes;
  bool _likeBusy = false;

  String get _uid => AuthService.instance.uid ?? '';
  bool get _isOwn => widget.video.userId == _uid;
  bool get _blockedBySpoiler => widget.video.isSpoiler && !_spoilerRevealed;

  @override
  void initState() {
    super.initState();
    _init();
    _loadLikeState();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.video.videoUrl));
    _ctrl = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(widget.muted ? 0 : 1);
      if (!mounted) return;
      setState(() => _ready = true);
      _syncPlayback();
    } catch (e) {
      debugPrint('[AniVideos] init ${widget.video.id} failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadLikeState() async {
    try {
      final liked = await AniVideoService.instance.isVideoLikedByUser(widget.video.id, _uid);
      if (mounted) setState(() => _liked = liked);
    } catch (_) {
      // Defaults stand; state self-corrects on the next successful toggle.
    }
  }

  @override
  void didUpdateWidget(covariant _VideoPage old) {
    super.didUpdateWidget(old);
    if (old.video.likes != widget.video.likes && !_likeBusy) _likes = widget.video.likes;
    final c = _ctrl;
    if (c == null || !_ready) return;
    if (old.muted != widget.muted) c.setVolume(widget.muted ? 0 : 1);
    if (old.isActive != widget.isActive) {
      if (!widget.isActive) {
        c.pause();
        c.seekTo(Duration.zero);
        _userPaused = false;
      }
      _syncPlayback();
    }
  }

  /// Play only when this page is the active one, the app is foregrounded
  /// (parent folds that into [isActive]), the user hasn't paused, and no
  /// spoiler cover is up.
  void _syncPlayback() {
    final c = _ctrl;
    if (c == null || !_ready) return;
    if (widget.isActive && !_userPaused && !_blockedBySpoiler) {
      c.play();
      AniVideoService.instance.incrementView(widget.video.id);
    } else {
      c.pause();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _ctrl;
    if (c == null || !_ready || _blockedBySpoiler) return;
    Haptics.light();
    setState(() => _userPaused = c.value.isPlaying);
    _syncPlayback();
  }

  Future<void> _toggleLike() async {
    Haptics.medium();
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += _liked ? 1 : -1;
    });
    if (_likeBusy) return;
    _likeBusy = true;
    try {
      if (wasLiked) {
        await AniVideoService.instance.unlikeVideo(widget.video.id, _uid);
      } else {
        await AniVideoService.instance.likeVideo(widget.video.id, _uid);
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

  void _errorSnack({required VoidCallback onRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ref.tr('actionFailed')),
      action: SnackBarAction(label: ref.tr('retry'), onPressed: onRetry),
    ));
  }

  void _share() {
    Haptics.light();
    Share.share('${widget.video.userName} on AniSphere 🎬\n\n${widget.video.caption}\n${widget.video.videoUrl}');
    AniVideoService.instance.incrementShareCount(widget.video.id);
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
                title: Text(ref.tr('deleteVideo'), style: AppTextStyles.body.copyWith(color: AppColors.secondary)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _confirmDelete();
                },
              )
            else
              ListTile(
                leading: const Icon(LucideIcons.flag, size: 20, color: AppColors.textSecondary),
                title: Text(ref.tr('reportVideo'), style: AppTextStyles.body),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showReportSheet();
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
        title: Text(ref.tr('deleteVideo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(ref.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(ref.tr('deleteVideo'), style: const TextStyle(color: AppColors.secondary)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AniVideoService.instance.deleteVideo(widget.video.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('videoDeleted'))));
    } catch (_) {
      if (!mounted) return;
      _errorSnack(onRetry: _confirmDelete);
    }
  }

  void _showReportSheet() {
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
            Text(ref.tr('whyReportVideo'), style: AppTextStyles.subheading),
            const SizedBox(height: 6),
            for (final (code, label) in reasons)
              ListTile(
                title: Text(label, style: AppTextStyles.body),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await AniVideoService.instance.reportVideo(widget.video.id, code);
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

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final c = _ctrl;
    final showVideo = _ready && c != null;
    final paused = showVideo && !c.value.isPlaying && !_blockedBySpoiler;

    return GestureDetector(
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail (or black) until the player's first frame is up.
          if (!showVideo && v.thumbnailUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: v.thumbnailUrl, fit: BoxFit.cover)
          else if (!showVideo)
            const ColoredBox(color: Colors.black),
          if (!_ready && !_failed)
            const Center(child: CircularProgressIndicator(color: Colors.white70, strokeWidth: 2)),
          if (_failed)
            const Center(child: Icon(LucideIcons.wifiOff, color: Colors.white38, size: 40)),
          if (showVideo)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            ),
          // Bottom scrim so the overlay text stays readable on bright video.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
          if (paused)
            const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 80)),

          // Stories-style playback position, pinned under the status bar.
          if (showVideo)
            Positioned(
              top: MediaQuery.of(context).padding.top + 48,
              left: 12,
              right: 12,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (_, value, __) {
                  final total = value.duration.inMilliseconds;
                  final progress = total > 0 ? value.position.inMilliseconds / total : 0.0;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 2.5,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primaryLight),
                    ),
                  );
                },
              ),
            ),

          // Right-side action rail.
          Positioned(
            right: 10,
            bottom: 110,
            child: Column(
              children: [
                _RailAction(
                  icon: _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  label: Fmt.compact(_likes),
                  color: _liked ? AppColors.secondary : Colors.white,
                  onTap: _toggleLike,
                ),
                _RailAction(
                  icon: LucideIcons.messageCircle,
                  label: Fmt.compact(v.commentsCount),
                  onTap: () {
                    Haptics.light();
                    showAniVideoCommentsSheet(context, v);
                  },
                ),
                _RailAction(icon: LucideIcons.share2, label: ref.tr('share'), onTap: _share),
                _RailAction(
                  icon: widget.muted ? LucideIcons.volumeX : LucideIcons.volume2,
                  onTap: () {
                    Haptics.light();
                    widget.onToggleMute();
                  },
                ),
                _RailAction(icon: LucideIcons.ellipsis, onTap: _showMoreMenu),
              ],
            ),
          ),

          // Bottom overlay: author, caption, anime chip.
          Positioned(
            left: 14,
            right: 74,
            bottom: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Live identity from users/{uid}; the video doc's copy is
                    // only the paint-first fallback.
                    Flexible(
                        child: Builder(builder: (context) {
                      final author = identityOf(ref, v.userId);
                      final handle = author?.userName ?? v.userName;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          UserAvatar(
                            name: author?.nameToShow ?? v.userName,
                            imageUrl: author?.userAvatar ?? v.userAvatar,
                            radius: 17,
                            onTap: () => context.push('/profile/${v.userId}'),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: GestureDetector(
                              onTap: () => context.push('/profile/${v.userId}'),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text('@$handle',
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.subheading.copyWith(color: Colors.white)),
                                  ),
                                  if (author?.isVerified ?? v.isVerified) ...[
                                    const SizedBox(width: 4),
                                    const VerifiedBadge(size: BadgeSize.sm),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    })),
                    if (!_isOwn) ...[
                      const SizedBox(width: 10),
                      FollowButton(userId: v.userId, compact: true),
                    ],
                  ],
                ),
                if (v.caption.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  HashtagText(
                    text: v.caption,
                    style: AppTextStyles.body.copyWith(color: Colors.white),
                  ),
                ],
                if (v.animeTitle != null && v.animeTitle!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _AnimeChip(video: v),
                ],
              ],
            ),
          ),

          // Spoiler cover — over everything except the rail/overlay chrome.
          if (_blockedBySpoiler)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  Haptics.light();
                  setState(() => _spoilerRevealed = true);
                  _syncPlayback();
                },
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    color: Colors.black45,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.eyeOff, color: Colors.white70, size: 36),
                        const SizedBox(height: 10),
                        Text(ref.tr('spoiler'),
                            style: AppTextStyles.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;
  const _RailAction({required this.icon, this.label, this.color = Colors.white, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Icon(icon, color: color, size: 29),
            if (label != null) ...[
              const SizedBox(height: 4),
              Text(label!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tagged-anime chip: cover + title → detail screen, "+" → Add to My List.
/// Same interaction contract as the feed's chip, restyled for dark overlay.
class _AnimeChip extends ConsumerStatefulWidget {
  final AniVideoData video;
  const _AnimeChip({required this.video});

  @override
  ConsumerState<_AnimeChip> createState() => _AnimeChipState();
}

class _AnimeChipState extends ConsumerState<_AnimeChip> {
  bool _adding = false;
  bool _added = false;

  Future<void> _addToList() async {
    final v = widget.video;
    if (v.anilistId == null || _adding || _added) return;
    Haptics.light();
    setState(() => _adding = true);
    try {
      await MyListService.instance
          .addToMyList(v.anilistId!, v.animeTitle ?? '', v.animeCover ?? '', ListStatus.planning);
      if (!mounted) return;
      setState(() => _added = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${v.animeTitle} → ${ref.tr('myList')} ✅')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('listError'))));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: GestureDetector(
              onTap: () {
                Haptics.light();
                if (v.anilistId != null) context.push('/trending/anime/${v.anilistId}');
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (v.animeCover != null && v.animeCover!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: CachedNetworkImage(imageUrl: v.animeCover!, width: 20, height: 28, fit: BoxFit.cover),
                    )
                  else
                    const Icon(LucideIcons.clapperboard, size: 13, color: AppColors.primaryLight),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(v.animeTitle!,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
          if (v.anilistId != null) ...[
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
