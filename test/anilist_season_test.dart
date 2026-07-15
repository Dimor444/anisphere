import 'package:anisphere/core/utils/anilist_season.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('aniListSeasonOf', () {
    test('July 2026 (current date) resolves to SUMMER 2026', () {
      expect(aniListSeasonOf(DateTime(2026, 7, 13)), (season: 'SUMMER', year: 2026));
    });

    test('season boundaries', () {
      expect(aniListSeasonOf(DateTime(2026, 1, 1)), (season: 'WINTER', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 2, 28)), (season: 'WINTER', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 3, 1)), (season: 'SPRING', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 5, 31)), (season: 'SPRING', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 6, 1)), (season: 'SUMMER', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 8, 31)), (season: 'SUMMER', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 9, 1)), (season: 'FALL', year: 2026));
      expect(aniListSeasonOf(DateTime(2026, 11, 30)), (season: 'FALL', year: 2026));
    });

    test('December rolls into next-year WINTER', () {
      expect(aniListSeasonOf(DateTime(2026, 12, 5)), (season: 'WINTER', year: 2027));
    });
  });

  group('display helpers', () {
    test('display name and emoji', () {
      expect(seasonDisplayName('SUMMER'), 'Summer');
      expect(seasonEmoji('SUMMER'), '☀️');
      expect(seasonEmoji('WINTER'), '❄️');
      expect(seasonEmoji('SPRING'), '🌸');
      expect(seasonEmoji('FALL'), '🍂');
    });
  });
}
