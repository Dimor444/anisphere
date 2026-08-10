import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/anilist_season.dart';
import '../../services/seasonal_service.dart';

/// The next 7 days of broadcasts, grouped by LOCAL weekday.
class WeeklySchedule {
  /// Kept for the header subtitle only — the season no longer filters
  /// anything, because `season`/`seasonYear` describe a show's PREMIERE
  /// season and would exclude every long-running series.
  final String season; // AniList enum, e.g. 'SUMMER'
  final int year;

  /// Weekday (DateTime.monday=1 … DateTime.sunday=7) → the episodes airing
  /// that day, chronological. Days with nothing airing are absent.
  ///
  /// One entry per AIRING, so a show broadcasting twice in the window appears
  /// under both days.
  final Map<int, List<AiringEntry>> byWeekday;

  const WeeklySchedule({required this.season, required this.year, required this.byWeekday});

  bool get isEmpty => byWeekday.isEmpty;

  /// Total airings across the week (not distinct shows).
  int get airingCount => byWeekday.values.fold(0, (sum, day) => sum + day.length);
}

/// Session-cached (Riverpod default). Retry / pull-to-refresh via
/// `ref.invalidate(weeklyScheduleProvider)` or
/// `ref.refresh(weeklyScheduleProvider.future)`.
final weeklyScheduleProvider = FutureProvider<WeeklySchedule>((ref) async {
  final now = DateTime.now();
  final s = aniListSeasonOf(now);
  final entries = await SeasonalService.instance.fetchWeek(from: now);

  final byWeekday = <int, List<AiringEntry>>{};
  for (final entry in entries) {
    // Each row's OWN airingAt. The previous implementation grouped by the
    // show-level nextAiringEpisode, which put a series on the weekday of its
    // next episode even when that episode fell outside the week entirely.
    byWeekday.putIfAbsent(entry.airingAt.toLocal().weekday, () => []).add(entry);
  }
  for (final day in byWeekday.values) {
    // Absolute time, so a rolling window that revisits a weekday (today's
    // remaining hours and the same weekday next week) still reads in order.
    day.sort((a, b) => a.airingAt.compareTo(b.airingAt));
  }
  return WeeklySchedule(season: s.season, year: s.year, byWeekday: byWeekday);
});
