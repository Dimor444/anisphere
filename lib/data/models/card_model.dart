import 'package:flutter/material.dart';

/// Gacha card rarities, from common to legendary.
enum CardRarity {
  common('Common', Color(0xFF94A3B8)),
  rare('Rare', Color(0xFF3B82F6)),
  epic('Epic', Color(0xFF8B5CF6)),
  legendary('Legendary', Color(0xFFF59E0B));

  final String label;
  final Color color;
  const CardRarity(this.label, this.color);
}

class CardModel {
  final String id;
  final String character;
  final String anime;
  final CardRarity rarity;
  final String emoji;
  final int power;
  final bool owned;

  /// Remote character artwork (e.g. AniList CDN). Preferred when set.
  final String? imageUrl;

  /// Bundled artwork asset (e.g. 'assets/images/cards/frieren.png').
  /// Used as an offline fallback if [imageUrl] is null or fails to load.
  final String? imagePath;

  const CardModel({
    required this.id,
    required this.character,
    required this.anime,
    required this.rarity,
    this.emoji = '⭐',
    this.power = 0,
    this.owned = false,
    this.imageUrl,
    this.imagePath,
  });
}
