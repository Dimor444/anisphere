import 'package:flutter_test/flutter_test.dart';

import 'package:anisphere/services/anime_dna_service.dart';
import 'package:anisphere/services/my_list_service.dart';

MyListEntry entry(int id, {double? score, DateTime? addedAt}) => MyListEntry(
      anilistId: id,
      title: 'anime-$id',
      coverImage: '',
      status: ListStatus.completed,
      score: score,
      addedAt: addedAt,
    );

void main() {
  final t0 = DateTime(2024, 1, 1);
  final t1 = DateTime(2024, 6, 1);

  group('deriveCardIds', () {
    test('ranks by user score, highest first', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [entry(1, score: 7), entry(2, score: 9.5), entry(3, score: 8)],
        pinned: const [],
      );
      expect(ids, [2, 3, 1]);
    });

    test('unrated entries rank below every rated one', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [entry(1), entry(2, score: 0), entry(3, score: 6)],
        pinned: const [],
      );
      // A 0 rating is still a rating — only truly unrated sinks to the end.
      expect(ids, [3, 2, 1]);
    });

    test('score ties break by addedAt ascending (earliest added wins)', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [entry(1, score: 8, addedAt: t1), entry(2, score: 8, addedAt: t0)],
        pinned: const [],
      );
      expect(ids, [2, 1]);
    });

    test('null addedAt (pending write) loses the tie; anilistId breaks the rest', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [
          entry(9, score: 8),
          entry(2, score: 8, addedAt: t0),
          entry(5, score: 8, addedAt: t0),
        ],
        pinned: const [],
      );
      expect(ids, [2, 5, 9]);
    });

    test('pinned ids fill first, in stored order, regardless of scores', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [entry(1, score: 10), entry(2, score: 9)],
        pinned: const [7, 3],
      );
      expect(ids, [7, 3, 1, 2]);
    });

    test('a pinned anime never duplicates its derived slot', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [entry(1, score: 10), entry(2, score: 9)],
        pinned: const [1],
      );
      expect(ids, [1, 2]);
    });

    test('caps at the card count, pinned taking precedence', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [for (var i = 1; i <= 10; i++) entry(i, score: i.toDouble())],
        pinned: const [100, 101],
      );
      expect(ids, [100, 101, 10, 9, 8]);
      expect(ids.length, AnimeDnaService.cardCap);
    });

    test('drops invalid pins (non-positive, duplicates) and id-0 entries', () {
      final ids = AnimeDnaService.deriveCardIds(
        entries: [entry(0, score: 10), entry(1, score: 5)],
        pinned: const [3, 3, -1, 0],
      );
      expect(ids, [3, 1]);
    });

    test('empty list and no pins → no slots (empty state, never samples)', () {
      expect(AnimeDnaService.deriveCardIds(entries: const [], pinned: const []), isEmpty);
    });
  });

  group('rankGenres', () {
    test('ranks by frequency, most frequent first', () {
      final genres = AnimeDnaService.rankGenres([
        ['Action', 'Drama'],
        ['Action', 'Fantasy'],
        ['Action', 'Drama'],
      ]);
      expect(genres, ['Action', 'Drama', 'Fantasy']);
    });

    test('frequency ties break alphabetically', () {
      final genres = AnimeDnaService.rankGenres([
        ['Romance', 'Comedy'],
      ]);
      expect(genres, ['Comedy', 'Romance']);
    });

    test('caps at the pill count and ignores empty strings', () {
      final genres = AnimeDnaService.rankGenres([
        ['A', 'B', 'C', 'D', 'E', 'F', ''],
      ]);
      expect(genres.length, AnimeDnaService.genreCap);
    });

    test('no genres → no pills', () {
      expect(AnimeDnaService.rankGenres(const []), isEmpty);
    });
  });
}
