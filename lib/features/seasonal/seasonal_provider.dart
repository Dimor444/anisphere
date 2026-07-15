import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/anilist_season.dart';
import '../../services/seasonal_service.dart';

/// The current season's airing schedule, grouped by LOCAL weekday.
class SeasonalSchedule {
  final String season; // AniList enum, e.g. 'SUMMER'
  final int year;

  /// Weekday (DateTime.monday=1 … DateTime.sunday=7) → shows airing that day,
  /// sorted ascending by airing time. Days with nothing airing are absent;
  /// shows with no `nextAiringEpisode` (finished for the season) are excluded.
  final Map<int, List<SeasonalAnime>> byWeekday;

  const SeasonalSchedule({required this.season, required this.year, required this.byWeekday});

  bool get isEmpty => byWeekday.isEmpty;
}

/// Session-cached (Riverpod default). Retry / pull-to-refresh via
/// `ref.invalidate(seasonalScheduleProvider)` or
/// `ref.refresh(seasonalScheduleProvider.future)`.
final seasonalScheduleProvider = FutureProvider<SeasonalSchedule>((ref) async {
  final s = aniListSeasonOf(DateTime.now());
  final list = await SeasonalService.instance.fetchSeason(season: s.season, year: s.year);

  final byWeekday = <int, List<SeasonalAnime>>{};
  for (final anime in list) {
    final at = anime.nextAiringAt;
    if (at == null) continue; // finished airing this season
    byWeekday.putIfAbsent(at.toLocal().weekday, () => []).add(anime);
  }
  for (final day in byWeekday.values) {
    day.sort((a, b) => a.nextAiringAt!.compareTo(b.nextAiringAt!));
  }
  return SeasonalSchedule(season: s.season, year: s.year, byWeekday: byWeekday);
});
