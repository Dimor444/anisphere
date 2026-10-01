// Shared title-matching helpers used to verify that an anime returned by a
// search actually corresponds to the requested name — so we never display a
// cover (or fetch a cast) from the wrong anime.

/// Lower-cases and strips punctuation so titles compare cleanly. Non-Latin
/// characters (e.g. kanji) collapse away — Latin/romaji titles carry the match.
String normalizeTitle(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Case-/punctuation-insensitive title match. Returns true when either title
/// contains the other, or they share a meaningful (4+ char) word — which
/// handles abbreviations like "FMA Brotherhood" → "Fullmetal Alchemist:
/// Brotherhood".
bool titleMatches(String requested, String candidate) {
  final r = normalizeTitle(requested);
  final c = normalizeTitle(candidate);
  if (r.isEmpty || c.isEmpty) return false;
  if (c.contains(r) || r.contains(c)) return true;

  final rWords = r.split(' ').where((w) => w.length >= 4).toSet();
  final cWords = c.split(' ').where((w) => w.length >= 4).toSet();
  return rWords.intersection(cWords).isNotEmpty;
}

/// True if one of an AniList media's MAIN titles (romaji / English / native)
/// is a reasonable match for [requested].
///
/// Synonyms are deliberately left out. AniList lists "Demon Slayer" as a
/// synonym of Onigiri, a 2016 short with harem cover art, which is why its
/// search ranks Onigiri first for that name; counting synonyms would wave it
/// straight through.
bool aniListMediaMatches(String requested, Map<String, dynamic> media) {
  final title = media['title'] as Map<String, dynamic>?;
  final candidates = <String?>[
    title?['romaji'] as String?,
    title?['english'] as String?,
    title?['native'] as String?,
  ];
  return candidates.any((c) => c != null && titleMatches(requested, c));
}

/// True if any of a Jikan `/anime` result's titles (default / English /
/// Japanese / synonyms) is a reasonable match for [requested].
bool jikanResultMatches(String requested, Map<String, dynamic> anime) {
  final candidates = <String?>[
    anime['title'] as String?,
    anime['title_english'] as String?,
    anime['title_japanese'] as String?,
  ];
  final titles = anime['titles'] as List<dynamic>?;
  if (titles != null) {
    for (final t in titles) {
      candidates.add((t as Map<String, dynamic>)['title'] as String?);
    }
  }
  return candidates.any((c) => c != null && titleMatches(requested, c));
}
