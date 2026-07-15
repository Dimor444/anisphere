import 'package:anisphere/services/chart_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChartService.currentSeason', () {
    test('maps months to seasons per spec', () {
      expect(ChartService.currentSeason(DateTime(2026, 1, 15)).season, 'WINTER');
      expect(ChartService.currentSeason(DateTime(2026, 3, 31)).season, 'WINTER');
      expect(ChartService.currentSeason(DateTime(2026, 4, 1)).season, 'SPRING');
      expect(ChartService.currentSeason(DateTime(2026, 6, 30)).season, 'SPRING');
      expect(ChartService.currentSeason(DateTime(2026, 7, 6)).season, 'SUMMER');
      expect(ChartService.currentSeason(DateTime(2026, 9, 30)).season, 'SUMMER');
      expect(ChartService.currentSeason(DateTime(2026, 10, 1)).season, 'FALL');
      expect(ChartService.currentSeason(DateTime(2026, 12, 31)).season, 'FALL');
    });

    test('carries the year through', () {
      expect(ChartService.currentSeason(DateTime(2026, 7, 6)).year, 2026);
    });
  });

  group('ChartService.computeMovements', () {
    test('positive = climbed, negative = dropped, absent = 0', () {
      final moves = ChartService.computeMovements(
        {1: 1, 2: 2, 3: 3}, // current ranks
        {1: 4, 2: 1, 9: 5}, // previous ranks (id 3 is new, id 9 fell out)
      );
      expect(moves[1], 3); // 4 → 1: up three
      expect(moves[2], -1); // 1 → 2: down one
      expect(moves[3], 0); // no history
    });

    test('empty history means all zero (no fake movement)', () {
      final moves = ChartService.computeMovements({10: 1, 20: 2}, const {});
      expect(moves.values.every((m) => m == 0), isTrue);
    });
  });

  group('AnimeChartEntry.fromMedia', () {
    test('parses AniList media, preferring the English title', () {
      final e = AnimeChartEntry.fromMedia({
        'id': 154587,
        'title': {'romaji': 'Sousou no Frieren', 'english': 'Frieren: Beyond Journey’s End'},
        'coverImage': {'large': 'https://img/x.png'},
        'averageScore': 91,
        'popularity': 453315,
      }, 1);
      expect(e.rank, 1);
      expect(e.anilistId, 154587);
      expect(e.title, startsWith('Frieren'));
      expect(e.score, closeTo(9.1, 0.001));
      expect(e.ratings, 453315);
      expect(e.movement, 0);
    });

    test('falls back to romaji and survives missing fields', () {
      final e = AnimeChartEntry.fromMedia({
        'id': 1,
        'title': {'romaji': 'Cowboy Bebop'},
      }, 42);
      expect(e.title, 'Cowboy Bebop');
      expect(e.rank, 42);
      expect(e.score, 0.0);
      expect(e.ratings, 0);
      expect(e.coverImage, '');
    });
  });
}
