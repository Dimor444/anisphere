import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../data/models/anime_model.dart';
import 'anime_cover_image.dart';
import 'pressable.dart';
import '../../core/constants/app_gradients.dart';

/// Gradient anime "poster" card. Used in feeds, grids, rails and selectors.
class AnimeCard extends StatelessWidget {
  final AnimeModel anime;
  final double width;
  final double height;
  final bool showScore;
  final bool showGenre;
  final bool selected;
  final bool selectable;
  final VoidCallback? onTap;
  final String? subtitle;

  const AnimeCard({
    super.key,
    required this.anime,
    this.width = 130,
    this.height = 175,
    this.showScore = true,
    this.showGenre = true,
    this.selected = false,
    this.selectable = false,
    this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap ?? () => context.push('/anime/${anime.id}'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
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
              // real AniList cover (falls back to gradient + emoji watermark)
              AnimeCoverImage(animeName: anime.title, gradient: anime.gradient, emoji: anime.emoji),
              // legibility scrim
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
              if (showScore)
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
                        Text(anime.score.toStringAsFixed(1),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
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
                    Text(
                      anime.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.1),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      )
                    else if (showGenre && anime.genre.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(anime.genre, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
              if (selectable && selected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded, color: AppGradients.onFill(AppColors.primary), size: 15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
