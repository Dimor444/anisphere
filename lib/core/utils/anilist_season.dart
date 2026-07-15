// Pure AniList season math — no Flutter imports so it stays unit-testable.

/// AniList `MediaSeason` + `seasonYear` for [date].
///
/// Dec → WINTER of NEXT year; Jan–Feb → WINTER; Mar–May → SPRING;
/// Jun–Aug → SUMMER; Sep–Nov → FALL.
// TODO(season-boundary): December → next-year WINTER matches how AniList files
// December premieres, but it's the one ambiguous boundary — verify against the
// live API near a Dec/Jan rollover.
({String season, int year}) aniListSeasonOf(DateTime date) {
  final m = date.month;
  if (m == DateTime.december) return (season: 'WINTER', year: date.year + 1);
  if (m <= DateTime.february) return (season: 'WINTER', year: date.year);
  if (m <= DateTime.may) return (season: 'SPRING', year: date.year);
  if (m <= DateTime.august) return (season: 'SUMMER', year: date.year);
  return (season: 'FALL', year: date.year);
}

/// 'SUMMER' → 'Summer' (header display case).
String seasonDisplayName(String season) =>
    season.isEmpty ? '' : season[0] + season.substring(1).toLowerCase();

/// Header emoji for each AniList season.
String seasonEmoji(String season) => switch (season) {
      'WINTER' => '❄️',
      'SPRING' => '🌸',
      'SUMMER' => '☀️',
      _ => '🍂',
    };
