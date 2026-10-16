import 'package:flutter/material.dart';
import '../../core/constants/app_gradients.dart';

enum WatchStatus { watching, completed, planning, onHold, dropped }

extension WatchStatusX on WatchStatus {
  String get label => switch (this) {
        WatchStatus.watching => 'Watching',
        WatchStatus.completed => 'Completed',
        WatchStatus.planning => 'Planning',
        WatchStatus.onHold => 'On Hold',
        WatchStatus.dropped => 'Dropped',
      };
}

class AnimeModel {
  final String id;

  /// The AniList entry this sample anime is, checked by hand against AniList's
  /// own record (title, first-season start year, format) — never looked up by
  /// searching the title, which is how "Demon Slayer" became Onigiri. Null
  /// means no verified entry, and nothing links anywhere for it.
  final int? anilistId;
  final String title;
  final String genre;
  final List<String> genres;
  final int year;
  final int episodes;
  final int watchedEp;
  final double score;
  final String status; // Airing / Finished / Upcoming
  final String emoji;
  final WatchStatus? myStatus;
  final double? myScore;
  final String note;
  final List<Color> palette; // signature 5-color palette

  const AnimeModel({
    required this.id,
    this.anilistId,
    required this.title,
    this.genre = '',
    this.genres = const [],
    this.year = 2024,
    this.episodes = 12,
    this.watchedEp = 0,
    this.score = 0,
    this.status = 'Finished',
    this.emoji = '🎬',
    this.myStatus,
    this.myScore,
    this.note = '',
    this.palette = const [],
  });

  /// Two-color gradient for posters / cards, derived from the title.
  LinearGradient get gradient => AppGradients.forSeed(title);
  List<Color> get gradientColors => AppGradients.pairForSeed(title);

  AnimeModel copyWith({
    WatchStatus? myStatus,
    double? myScore,
    String? note,
    int? watchedEp,
  }) {
    return AnimeModel(
      id: id,
      anilistId: anilistId,
      title: title,
      genre: genre,
      genres: genres,
      year: year,
      episodes: episodes,
      watchedEp: watchedEp ?? this.watchedEp,
      score: score,
      status: status,
      emoji: emoji,
      myStatus: myStatus ?? this.myStatus,
      myScore: myScore ?? this.myScore,
      note: note ?? this.note,
      palette: palette,
    );
  }
}
