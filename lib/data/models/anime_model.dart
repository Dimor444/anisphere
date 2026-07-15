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
  final String title;
  final String japaneseTitle;
  final String studio;
  final String genre;
  final List<String> genres;
  final int year;
  final int episodes;
  final int watchedEp;
  final double score;
  final int ratingCount;
  final String status; // Airing / Finished / Upcoming
  final String emoji;
  final WatchStatus? myStatus;
  final double? myScore;
  final String note;
  final int watchingNow; // users watching on AniSphere
  final List<Color> palette; // signature 5-color palette

  const AnimeModel({
    required this.id,
    required this.title,
    this.japaneseTitle = '',
    this.studio = '',
    this.genre = '',
    this.genres = const [],
    this.year = 2024,
    this.episodes = 12,
    this.watchedEp = 0,
    this.score = 0,
    this.ratingCount = 0,
    this.status = 'Finished',
    this.emoji = '🎬',
    this.myStatus,
    this.myScore,
    this.note = '',
    this.watchingNow = 0,
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
      title: title,
      japaneseTitle: japaneseTitle,
      studio: studio,
      genre: genre,
      genres: genres,
      year: year,
      episodes: episodes,
      watchedEp: watchedEp ?? this.watchedEp,
      score: score,
      ratingCount: ratingCount,
      status: status,
      emoji: emoji,
      myStatus: myStatus ?? this.myStatus,
      myScore: myScore ?? this.myScore,
      note: note ?? this.note,
      watchingNow: watchingNow,
      palette: palette,
    );
  }
}
