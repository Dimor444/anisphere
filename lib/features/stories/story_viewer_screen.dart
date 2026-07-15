import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../services/story_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';
import 'story_providers.dart';

/// Full-screen viewer for one user's active stories: progress bars,
/// auto-advance (5s per story), tap left/right to navigate, hold to pause,
/// swipe down to close. Views are recorded create-only per story; the owner
/// can delete the story being shown.
class StoryViewerScreen extends ConsumerStatefulWidget {
  final StoryGroup group;
  const StoryViewerScreen({super.key, required this.group});

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _perStory = Duration(seconds: 5);

  late final List<StoryData> _stories = List.of(widget.group.stories);
  late final AnimationController _c;
  int _index = 0;
  String? _myUid;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _perStory)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _advance();
      });
    _c.forward();
    ref.read(myUidProvider.future).then((uid) {
      if (mounted) setState(() => _myUid = uid);
      _recordView();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  StoryData get _current => _stories[_index];

  bool get _isOwner => _myUid != null && _myUid == _current.uid;

  /// Create-only viewer write for the story on screen; own stories skipped.
  void _recordView() {
    if (_myUid == null || _current.uid == _myUid) return;
    markStoryViewed(ref, _current.id);
  }

  void _advance() {
    if (_index < _stories.length - 1) {
      setState(() => _index++);
      _recordView();
      _c.forward(from: 0);
    } else {
      Navigator.pop(context);
    }
  }

  void _back() {
    if (_index > 0) {
      setState(() => _index--);
      _c.forward(from: 0);
    } else {
      _c.forward(from: 0); // first story: restart its timer
    }
  }

  /// Sticker hotspot tapped: pause playback, deep-link, resume on return.
  /// Anime tags go through the shared AniList detail path
  /// (/trending/anime/:id → fetchById) — never /anime/:id, which is keyed to
  /// SampleData ids. Mentions go to the shared /profile/:uid route.
  Future<void> _openLink(String location) async {
    Haptics.light();
    _c.stop();
    await context.push(location);
    if (mounted && !_deleting) _c.forward();
  }

  Future<void> _confirmDelete() async {
    _c.stop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete story?'),
        content: const Text('This removes it for everyone immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      _c.forward();
      return;
    }
    setState(() => _deleting = true);
    try {
      await StoryService.instance.deleteStory(_current);
      if (!mounted) return;
      _stories.removeAt(_index);
      if (_stories.isEmpty) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _deleting = false;
        if (_index >= _stories.length) _index = _stories.length - 1;
      });
      _c.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't delete the story. Try again.")));
      _c.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _current;
    final user = identityOf(ref, story.uid);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          if (_deleting) return;
          final w = MediaQuery.of(context).size.width;
          d.globalPosition.dx < w / 3 ? _back() : _advance();
        },
        onLongPressStart: (_) => _c.stop(),
        onLongPressEnd: (_) {
          if (!_deleting) _c.forward();
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 0) Navigator.pop(context);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: story.mediaUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
                errorWidget: (_, __, ___) =>
                    const Center(child: Icon(LucideIcons.imageOff, color: Colors.white38, size: 44)),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent, Colors.black87],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
            ),
            // Tap hotspots over the baked stickers — the anime tag and every
            // mention (below the chrome, so the top-bar buttons still win
            // where they overlap).
            if (story.animeTag != null || story.mentions.isNotEmpty)
              Positioned.fill(
                child: _StoryHotspots(
                  key: ValueKey('hotspots-${story.id}'),
                  mediaUrl: story.mediaUrl,
                  entries: [
                    if (story.animeTag != null)
                      (
                        x: story.animeTag!.x,
                        y: story.animeTag!.y,
                        w: story.animeTag!.w,
                        h: story.animeTag!.h,
                        onTap: () {
                          if (!_deleting) _openLink('/trending/anime/${story.animeTag!.anilistId}');
                        },
                      ),
                    for (final m in story.mentions)
                      (
                        x: m.x,
                        y: m.y,
                        w: m.w,
                        h: m.h,
                        onTap: () {
                          if (!_deleting) _openLink('/profile/${m.uid}');
                        },
                      ),
                  ],
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: List.generate(_stories.length, (i) {
                        return Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                            child: i == _index
                                ? AnimatedBuilder(
                                    animation: _c,
                                    builder: (_, __) => FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: _c.value,
                                      child: Container(
                                          decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(2))),
                                    ),
                                  )
                                : (i < _index
                                    ? Container(
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(2)))
                                    : null),
                          ),
                        );
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        UserAvatar(
                            name: user?.nameToShow ?? '…', imageUrl: user?.userAvatar, radius: 18),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(user?.nameToShow ?? '…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.subheading),
                        ),
                        if (user?.isVerified == true) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: BadgeSize.sm),
                        ],
                        const SizedBox(width: 6),
                        if (story.createdAt != null)
                          Text(Fmt.timeAgo(story.createdAt!), style: AppTextStyles.captionMuted),
                        const Spacer(),
                        if (_isOwner)
                          IconButton(
                            icon: const Icon(LucideIcons.trash2, color: Colors.white, size: 20),
                            onPressed: _deleting ? null : _confirmDelete,
                          ),
                        IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (story.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                      child: Text(story.caption,
                          style: AppTextStyles.heading.copyWith(color: Colors.white)),
                    ),
                ],
              ),
            ),
            if (_deleting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black45,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One tappable sticker region: rect as fractions of the image + action.
typedef _HotspotEntry = ({double x, double y, double w, double h, VoidCallback onTap});

/// Invisible tap targets laid exactly over the baked stickers (anime tag,
/// mentions). Each rect is normalized to the IMAGE (fractions of
/// width/height, written by the editor at flatten time); this widget
/// resolves the image's intrinsic size once, computes the contain-fitted
/// rect on this screen, and maps every entry into it — so the hotspots land
/// on their sticker pixels on any screen size.
class _StoryHotspots extends StatefulWidget {
  final String mediaUrl;
  final List<_HotspotEntry> entries;
  const _StoryHotspots({super.key, required this.mediaUrl, required this.entries});

  @override
  State<_StoryHotspots> createState() => _StoryHotspotsState();
}

class _StoryHotspotsState extends State<_StoryHotspots> {
  Size? _imageSize;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_StoryHotspots old) {
    super.didUpdateWidget(old);
    if (old.mediaUrl != widget.mediaUrl) {
      _detach();
      _imageSize = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _resolve() {
    // Same provider the on-screen CachedNetworkImage uses, so this resolves
    // from cache the moment the story image itself is shown.
    _listener = ImageStreamListener((info, _) {
      if (mounted) {
        setState(() => _imageSize = Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      info.dispose();
    }, onError: (_, __) {});
    _stream = CachedNetworkImageProvider(widget.mediaUrl).resolve(ImageConfiguration.empty)
      ..addListener(_listener!);
  }

  void _detach() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;
    if (imageSize == null || imageSize.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final box = constraints.biggest;
      final fitted = applyBoxFit(BoxFit.contain, imageSize, box).destination;
      final imageRect = Alignment.center.inscribe(fitted, Offset.zero & box);
      return Stack(children: [
        for (final e in widget.entries)
          Positioned.fromRect(
            rect: Rect.fromLTWH(
              imageRect.left + e.x * imageRect.width,
              imageRect.top + e.y * imageRect.height,
              e.w * imageRect.width,
              e.h * imageRect.height,
            ),
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: e.onTap),
          ),
      ]);
    });
  }
}

/// Fallback when the route is opened without a [StoryGroup] extra (deep link
/// or stale navigation) — nothing to play, so offer the way back.
class StoryViewerFallback extends StatelessWidget {
  const StoryViewerFallback({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: const Center(
        child: Text('This story is no longer available.', style: AppTextStyles.bodyMuted),
      ),
    );
  }
}
