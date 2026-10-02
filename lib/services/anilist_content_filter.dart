// The line the app draws on AniList titles beyond `isAdult: false`, which
// marks explicit titles only: no Ecchi genre, and no Nudity tag ranked
// above [kNudityMinRank] (out of 100) by AniList's voters.
//
// Queries that accept the arguments splice in [kAniListContentArgs]. Where a
// field takes no such argument (airingSchedules, characters), or where rows
// must keep their place in AniList's own order (the chart and Observatory's
// popular list, so a removed row leaves a visible gap in the numbering rather
// than renumbering everything after it), the response is checked with
// [overContentLine] instead — the same rule, applied in the app.
//
// Applied where a user browses or searches. Not applied to lookups of a title
// that is already on screen — by id (detail page, My List, Anime DNA, True Fan
// profile) or by a fixed sample name (covers, the True Fan cast): there it
// hides nothing, it only blanks the entry pointing at the title.

/// A Nudity tag counts when ranked ABOVE this (out of 100) — AniList's own
/// `minimumTagRank` keeps a tag at exactly this rank, so [overContentLine]
/// does too. At AniList's default of 18 the tag took Cowboy Bebop, Evangelion
/// and Akira; at 70 it keeps them and still catches Kill la Kill (85) and
/// High School DxD (96).
const int kNudityMinRank = 70;

/// The line as AniList query arguments. `minimumTagRank` scopes the tag
/// filter only, so the genre exclusion is unaffected by it.
const String kAniListContentArgs =
    'genre_not_in: ["Ecchi"], tag_not_in: ["Nudity"], minimumTagRank: $kNudityMinRank';

/// True if [media] — an AniList Media map selected with `genres` and
/// `tags { name rank }` — falls outside the app's content line.
bool overContentLine(Map<String, dynamic> media) {
  final genres = (media['genres'] as List<dynamic>?) ?? const [];
  if (genres.contains('Ecchi')) return true;
  final tags = (media['tags'] as List<dynamic>?) ?? const [];
  return tags.any((t) {
    final tag = t as Map<String, dynamic>;
    return tag['name'] == 'Nudity' && ((tag['rank'] as num?) ?? 0) > kNudityMinRank;
  });
}
