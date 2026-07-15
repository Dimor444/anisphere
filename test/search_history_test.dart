import 'package:anisphere/features/discover/search_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchHistory.addTo', () {
    test('inserts at front and caps at 8', () {
      var h = <String>[];
      for (var i = 1; i <= 9; i++) {
        h = SearchHistory.addTo(h, 'search $i');
      }
      expect(h.length, 8);
      expect(h.first, 'search 9');
      expect(h.contains('search 1'), isFalse, reason: 'oldest drops past the cap');
    });

    test('re-search moves to front instead of duplicating (case-insensitive)', () {
      var h = SearchHistory.addTo([], 'One Piece');
      h = SearchHistory.addTo(h, 'frieren');
      h = SearchHistory.addTo(h, 'one piece');
      expect(h.length, 2);
      expect(h.first, 'one piece');
      expect(h.where((e) => e.toLowerCase() == 'one piece').length, 1);
    });

    test('rejects junk: short and whitespace-padded-short queries', () {
      expect(SearchHistory.addTo([], 'd'), isEmpty);
      expect(SearchHistory.addTo([], '  a  '), isEmpty);
      expect(SearchHistory.addTo([], ''), isEmpty);
      expect(SearchHistory.addTo(['kept'], 'x'), ['kept']);
    });

    test('trims before saving and deduping', () {
      var h = SearchHistory.addTo([], '  dr. stone  ');
      expect(h, ['dr. stone']);
      h = SearchHistory.addTo(h, 'DR. STONE');
      expect(h.length, 1);
    });
  });

  group('SearchHistory.sanitize (v1 migration)', () {
    test('strips keystroke fragments, keeping the completed search', () {
      final cleaned = SearchHistory.sanitize(
          ['dr. stone', 'dr. ston', 'dr. sto', 'dr. st', 'dr. s', 'dr.', 'dr', 'dr s']);
      expect(cleaned, ['dr. stone', 'dr s']); // "dr s" isn't a prefix — ages out naturally
    });

    test('dedupes case-insensitively keeping the newest, caps at 8', () {
      final cleaned = SearchHistory.sanitize([
        'One Piece', 'one piece', 'frieren', 'a', // junk
        's1', 's2', 's3', 's4', 's5', 's6', 's7',
      ]);
      expect(cleaned.length, 8);
      expect(cleaned.first, 'One Piece');
      expect(cleaned.where((e) => e.toLowerCase() == 'one piece').length, 1);
      expect(cleaned.contains('a'), isFalse);
    });

    test('empty input survives', () {
      expect(SearchHistory.sanitize([]), isEmpty);
    });
  });
}
