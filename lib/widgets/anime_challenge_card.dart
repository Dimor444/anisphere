import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_gradients.dart';
import '../services/anime_image_service.dart';

/// A poster-style card for the Challenges "True Fan" grid.
///
/// Fetches the anime's real cover image via [AnimeImageService] (Jikan, with an
/// AniList fallback) and overlays the title, a genre chip and a star-rating
/// badge. While the image is resolving a [CircularProgressIndicator] is shown.
/// On failure it falls back to the first letter of the anime name — or a
/// `wifi_off` icon when the device is offline — with a Retry button so the user
/// can reload manually.
class AnimeChallengeCard extends StatefulWidget {
  final String animeName;
  final String genre;
  final double rating;
  final VoidCallback? onTap;

  /// Optional selection highlight — used by the True Fan picker so the chosen
  /// anime gets a glowing border + check badge.
  final bool selected;

  const AnimeChallengeCard({
    super.key,
    required this.animeName,
    required this.genre,
    required this.rating,
    this.onTap,
    this.selected = false,
  });

  @override
  State<AnimeChallengeCard> createState() => _AnimeChallengeCardState();
}

class _AnimeChallengeCardState extends State<AnimeChallengeCard> {
  late Future<AnimeImageResult> _imageFuture;

  @override
  void initState() {
    super.initState();
    _imageFuture = AnimeImageService.instance.fetchImage(widget.animeName);
  }

  @override
  void didUpdateWidget(covariant AnimeChallengeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animeName != widget.animeName) {
      _imageFuture = AnimeImageService.instance.fetchImage(widget.animeName);
    }
  }

  /// Re-runs the lookup. Transient failures aren't cached, so this genuinely
  /// re-hits the network; a definitive miss resolves instantly from cache.
  void _reload() {
    setState(() {
      _imageFuture = AnimeImageService.instance.fetchImage(widget.animeName);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.selected ? AppColors.primary : Colors.transparent,
            width: 2.4,
          ),
          // Selection is carried by the border above; the neutral black
          // elevation shadow stays.
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(),

              // Bottom gradient overlay for legibility.
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

              // Star rating badge (top-left).
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 13),
                      const SizedBox(width: 2),
                      Text(
                        widget.rating.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),

              // Selection check (top-right).
              if (widget.selected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded, color: AppGradients.onFill(AppColors.primary), size: 15),
                  ),
                ),

              // Title + genre chip (bottom).
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.animeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    if (widget.genre.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.genre,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
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

  /// Resolves the image URL, then loads it (cached). Shows a spinner while the
  /// URL is being fetched; on a miss shows the letter fallback, and when the
  /// device is offline shows a wifi-off icon. Both fallbacks carry a Retry tap.
  Widget _buildImage() {
    return FutureBuilder<AnimeImageResult>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loading();
        }
        final result = snapshot.data;
        if (result != null && result.status == ImageFetchStatus.found && result.url != null) {
          return CachedNetworkImage(
            imageUrl: result.url!,
            fit: BoxFit.cover,
            placeholder: (_, __) => _loading(),
            errorWidget: (_, __, ___) => _fallback(offline: false),
          );
        }
        return _fallback(offline: result?.status == ImageFetchStatus.offline);
      },
    );
  }

  Widget _loading() => DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.forSeed(widget.animeName)),
        child: const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          ),
        ),
      );

  /// Fallback tile: a `wifi_off` icon when [offline], otherwise the first letter
  /// of the anime name. Always includes a Retry button.
  Widget _fallback({required bool offline}) {
    final name = widget.animeName.trim();
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppGradients.forSeed(widget.animeName)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (offline)
              const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 40)
            else
              Text(
                letter,
                style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 8),
            _retryButton(),
          ],
        ),
      ),
    );
  }

  Widget _retryButton() {
    return GestureDetector(
      onTap: _reload,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 13),
            SizedBox(width: 4),
            Text('Retry', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
