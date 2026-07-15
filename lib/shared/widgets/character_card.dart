import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/models/card_model.dart';

/// A reusable collectible character card.
///
/// Renders a character image behind a rarity badge (top-left), the character
/// name + series (bottom-left) and a power stat with a lightning icon. A dark
/// bottom gradient keeps the text readable over any artwork.
///
/// Pass [imagePath] to show artwork from `assets/`. If it is null — or the file
/// can't be loaded yet — [fallbackEmoji] is drawn on the rarity gradient
/// instead, so cards always render cleanly even before the art is added.
///
/// Example:
/// ```dart
/// CharacterCard(
///   imagePath: 'assets/images/cards/frieren.png',
///   characterName: 'Frieren',
///   seriesName: 'Frieren',
///   rarity: CardRarity.legendary,
///   power: 9800,
///   fallbackEmoji: '🧝‍♀️',
/// )
/// ```
class CharacterCard extends StatelessWidget {
  /// Remote artwork (preferred when set, e.g. AniList CDN).
  final String? imageUrl;

  /// Bundled asset artwork — offline fallback if [imageUrl] is null/fails.
  final String? imagePath;
  final String characterName;
  final String seriesName;
  final CardRarity rarity;
  final int power;

  /// Shown when neither [imageUrl] nor [imagePath] resolves.
  final String? fallbackEmoji;

  /// Dims the card and shows a lock — use for not-yet-owned cards.
  final bool dimmed;

  const CharacterCard({
    super.key,
    this.imageUrl,
    this.imagePath,
    required this.characterName,
    required this.seriesName,
    required this.rarity,
    required this.power,
    this.fallbackEmoji,
    this.dimmed = false,
  });

  /// Background gradient tied to rarity (gold = Legendary, purple = Epic, …).
  List<Color> get _gradient => switch (rarity) {
        CardRarity.common => const [Color(0xFF475569), Color(0xFF1E293B)],
        CardRarity.rare => const [Color(0xFF3B82F6), Color(0xFF1E3A8A)],
        CardRarity.epic => const [Color(0xFF8B5CF6), Color(0xFF5B21B6)],
        CardRarity.legendary => const [Color(0xFFF59E0B), Color(0xFFB45309)],
      };

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Container(
        // Gradient + border + (legendary) glow live on the outer container so
        // the glow isn't clipped; ClipRRect below rounds the artwork & overlay.
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: radius,
          border: Border.all(color: rarity.color, width: 2),
          boxShadow: rarity == CardRarity.legendary && !dimmed
              ? [BoxShadow(color: rarity.color.withOpacity(0.6), blurRadius: 18)]
              : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── 1. Character artwork (behind everything).
              _ArtLayer(imageUrl: imageUrl, imagePath: imagePath, fallbackEmoji: fallbackEmoji),

              // ── 2. Legibility overlay: a touch of dark at the very top (so the
              //       rarity badge reads), clear through the middle, strong dark
              //       at the bottom (so name/series/power stay readable).
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black26, Colors.transparent, Colors.black87],
                    stops: [0.0, 0.4, 1.0],
                  ),
                ),
              ),

              // ── 3. Rarity badge (top-left).
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(rarity.label, style: TextStyle(color: rarity.color, fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),

              // ── 4. Lock for not-yet-owned cards.
              if (dimmed) const Center(child: Icon(LucideIcons.lock, color: Colors.white, size: 22)),

              // ── 5. Name / series / power (bottom-left).
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(characterName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    Text(seriesName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(LucideIcons.zap, size: 11, color: Colors.white),
                      const SizedBox(width: 3),
                      Text('$power', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
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

/// Resolves the artwork in priority order: remote [imageUrl] → bundled
/// [imagePath] → centred [fallbackEmoji]. All cover-fitted, top-aligned.
class _ArtLayer extends StatelessWidget {
  final String? imageUrl;
  final String? imagePath;
  final String? fallbackEmoji;
  const _ArtLayer({required this.imageUrl, required this.imagePath, required this.fallbackEmoji});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, __) => _emoji(),
        errorWidget: (_, __, ___) => _asset(),
      );
    }
    return _asset();
  }

  // Bundled-asset layer (offline fallback), itself falling back to the emoji.
  Widget _asset() {
    if (imagePath == null) return _emoji();
    return Image.asset(
      imagePath!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (_, __, ___) => _emoji(),
    );
  }

  Widget _emoji() => Center(child: Text(fallbackEmoji ?? '⭐', style: const TextStyle(fontSize: 56)));
}
