import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../services/anime_image_service.dart';

/// Fills its box with a real anime cover fetched from [AnimeImageService]
/// (AniList) — the same approach the True Fan cards use.
///
/// While the URL resolves / the image downloads it shows the [gradient] with a
/// small spinner; if the lookup or download fails it falls back to the
/// [gradient] + [emoji] watermark. Drop it in as the base layer of any anime
/// card or poster (e.g. inside a `Stack` with `StackFit.expand`).
class AnimeCoverImage extends StatefulWidget {
  final String animeName;
  final Gradient gradient;
  final String emoji;
  final double emojiSize;

  /// High priority for gameplay-critical covers; low (default) for thumbnails,
  /// so the AniList rate budget favours interactive content.
  final bool priority;

  const AnimeCoverImage({
    super.key,
    required this.animeName,
    required this.gradient,
    this.emoji = '🎬',
    this.emojiSize = 64,
    this.priority = false,
  });

  @override
  State<AnimeCoverImage> createState() => _AnimeCoverImageState();
}

class _AnimeCoverImageState extends State<AnimeCoverImage> {
  late Future<AnimeImageResult> _future;

  @override
  void initState() {
    super.initState();
    _future = AnimeImageService.instance.fetchImage(widget.animeName, priority: widget.priority);
  }

  @override
  void didUpdateWidget(covariant AnimeCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animeName != widget.animeName) {
      _future = AnimeImageService.instance.fetchImage(widget.animeName, priority: widget.priority);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnimeImageResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return _loading();
        final result = snapshot.data;
        if (result != null && result.status == ImageFetchStatus.found && result.url != null) {
          return CachedNetworkImage(
            imageUrl: result.url!,
            fit: BoxFit.cover,
            placeholder: (_, __) => _loading(),
            errorWidget: (_, __, ___) => _fallback(),
          );
        }
        return _fallback();
      },
    );
  }

  Widget _loading() => DecoratedBox(
        decoration: BoxDecoration(gradient: widget.gradient),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
        ),
      );

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(gradient: widget.gradient),
        child: Center(child: Text(widget.emoji, style: TextStyle(fontSize: widget.emojiSize))),
      );
}
