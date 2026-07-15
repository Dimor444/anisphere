import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Progression levels — each unlocks a distinct avatar "aura" glow.
enum UserLevel {
  newbie('Newbie', '🌱', AuraType.none),
  animeFan('Anime Fan', '🎬', AuraType.white),
  otaku('Otaku', '🗾', AuraType.blue),
  weeb('Weeb', '🔥', AuraType.orange),
  otakuElite('Otaku Elite', '👑', AuraType.purpleShimmer),
  weebGod('Weeb God', '🌟', AuraType.rainbowGold);

  final String label;
  final String emoji;
  final AuraType aura;
  const UserLevel(this.label, this.emoji, this.aura);

  String get title => '$label $emoji';

  List<Color> get gradient => switch (this) {
        UserLevel.newbie => const [Color(0xFF64748B), Color(0xFF334155)],
        UserLevel.animeFan => const [Color(0xFF22D3EE), Color(0xFF3B82F6)],
        UserLevel.otaku => const [Color(0xFF3B82F6), Color(0xFF6366F1)],
        UserLevel.weeb => const [Color(0xFFF97316), Color(0xFFEF4444)],
        UserLevel.otakuElite => const [AppColors.primary, AppColors.secondary],
        UserLevel.weebGod => const [Color(0xFFFACC15), Color(0xFFF59E0B)],
      };

  static UserLevel fromLabel(String label) {
    return UserLevel.values.firstWhere(
      (l) => l.label == label,
      orElse: () => UserLevel.animeFan,
    );
  }
}

enum AuraType { none, white, blue, orange, purpleShimmer, rainbowGold }

class UserModel {
  final String id;
  final String username;
  final String? displayName;
  final String bio;
  final UserLevel level;
  final bool isVerified;
  final bool isPlusUser;
  final int watchedAnime;
  final int episodes;
  final int hours;
  final int following;
  final int followers;
  final int streak;
  final String memberSince;
  final int trueFanRank;
  final int aniGold;
  final int aniGem;
  final List<String> topAnime; // titles
  final List<String> genres;
  final String firstAnime;
  final String country; // emoji flag
  final bool isFollowedByMe;

  const UserModel({
    required this.id,
    required this.username,
    this.displayName,
    this.bio = '',
    this.level = UserLevel.animeFan,
    this.isVerified = false,
    this.isPlusUser = false,
    this.watchedAnime = 0,
    this.episodes = 0,
    this.hours = 0,
    this.following = 0,
    this.followers = 0,
    this.streak = 0,
    this.memberSince = '',
    this.trueFanRank = 0,
    this.aniGold = 0,
    this.aniGem = 0,
    this.topAnime = const [],
    this.genres = const [],
    this.firstAnime = '',
    this.country = '🌍',
    this.isFollowedByMe = false,
  });

  UserModel copyWith({
    String? bio,
    bool? isPlusUser,
    bool? isVerified,
    int? aniGold,
    int? aniGem,
    int? streak,
    bool? isFollowedByMe,
    int? followers,
  }) {
    return UserModel(
      id: id,
      username: username,
      displayName: displayName,
      bio: bio ?? this.bio,
      level: level,
      isVerified: isVerified ?? this.isVerified,
      isPlusUser: isPlusUser ?? this.isPlusUser,
      watchedAnime: watchedAnime,
      episodes: episodes,
      hours: hours,
      following: following,
      followers: followers ?? this.followers,
      streak: streak ?? this.streak,
      memberSince: memberSince,
      trueFanRank: trueFanRank,
      aniGold: aniGold ?? this.aniGold,
      aniGem: aniGem ?? this.aniGem,
      topAnime: topAnime,
      genres: genres,
      firstAnime: firstAnime,
      country: country,
      isFollowedByMe: isFollowedByMe ?? this.isFollowedByMe,
    );
  }
}
