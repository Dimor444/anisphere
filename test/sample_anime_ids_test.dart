import 'package:anisphere/data/sample_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every sample anime carries its own verified AniList id', () {
    final ids = SampleData.animeList.map((a) => a.anilistId).toList();
    expect(ids, everyElement(isNotNull));
    expect(ids.toSet().length, ids.length, reason: 'two sample anime point at one AniList entry');
  });

  test('a title resolves only when it is exactly a sample title', () {
    expect(SampleData.anilistIdForTitle('Frieren'), 154587);
    expect(SampleData.anilistIdForTitle('Demon Slayer: Kimetsu no Yaiba'), 101922);
    // The bare title that searched to Onigiri, and anything unknown: no link,
    // where the old lookup opened Naruto.
    expect(SampleData.anilistIdForTitle('Demon Slayer'), isNull);
    expect(SampleData.anilistIdForTitle('Not An Anime'), isNull);
    expect(SampleData.anilistIdForTitle(null), isNull);
  });
}
