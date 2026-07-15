import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';

/// One entry in the current season's lineup, straight from AniList.
///
/// Referenced by AniList id only — Seasonal is a read-only feature, no
/// Firestore document backs this model.
class SeasonalAnime {
  final int id; // anilist_id
  final String title; // english ?? romaji
  final String coverUrl;
  final int? episodes; // announced episode count, if known
  final String status; // RELEASING / NOT_YET_RELEASED / … ('' if unknown)
  final String format; // TV / ONA / MOVIE / … ('' if unknown)
  final int? nextEpisode; // upcoming episode number; null once finished
  final DateTime? nextAiringAt; // local time of that episode; null once finished

  const SeasonalAnime({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.episodes,
    required this.status,
    required this.format,
    required this.nextEpisode,
    required this.nextAiringAt,
  });
}

/// Current-season lineup backed by AniList GraphQL.
///
/// Stateless fetcher: the seasonal Riverpod provider is the session cache, so
/// invalidating the provider is what triggers a refetch. Throws on network
/// failure so the UI can show error + retry.
class SeasonalService {
  SeasonalService._();
  static final SeasonalService instance = SeasonalService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  static const String _query = r'''
query ($season: MediaSeason, $seasonYear: Int, $page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage total }
    media(season: $season, seasonYear: $seasonYear, type: ANIME, isAdult: false, sort: POPULARITY_DESC) {
      id
      title { romaji english native }
      coverImage { large extraLarge color }
      episodes
      status
      format
      nextAiringEpisode { airingAt timeUntilAiring episode }
    }
  }
}''';

  /// The season's anime, most popular first (page 1, up to 50 entries).
  /// [season] is the AniList enum string (e.g. 'SUMMER'), from
  /// `aniListSeasonOf`.
  Future<List<SeasonalAnime>> fetchSeason({required String season, required int year}) async {
    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_endpoint),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode(<String, dynamic>{
                'query': _query,
                'variables': <String, dynamic>{
                  'season': season,
                  'seasonYear': year,
                  'page': 1,
                  'perPage': 50,
                },
              }),
            )
            .timeout(_timeout),
        priority: true, // user is on the screen waiting
      );

      if (res.statusCode != 200) {
        debugPrint('[SeasonalService] AniList request FAILED: status ${res.statusCode}\n${res.body}');
        throw HttpException('AniList returned ${res.statusCode}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final page = (body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
      final media = page?['media'] as List<dynamic>?;
      if (media == null) throw const FormatException('Unexpected AniList response shape');

      final results = <SeasonalAnime>[];
      final seen = <int>{};
      for (final m in media) {
        final anime = _parseMedia(m as Map<String, dynamic>);
        if (anime == null || !seen.add(anime.id)) continue;
        results.add(anime);
      }
      debugPrint('[SeasonalService] fetched ${results.length} anime for $season $year.');
      return results;
    } on SocketException catch (e) {
      debugPrint('[SeasonalService] socket error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[SeasonalService] timeout: $e');
      rethrow;
    }
  }

  /// AniList media map → model. Null when id/title are unusable.
  SeasonalAnime? _parseMedia(Map<String, dynamic> map) {
    final id = map['id'] as int?;
    if (id == null) return null;
    final title = map['title'] as Map<String, dynamic>?;
    final name = (title?['english'] ?? title?['romaji']) as String?;
    if (name == null || name.trim().isEmpty) return null;

    final cover = map['coverImage'] as Map<String, dynamic>?;
    final airing = map['nextAiringEpisode'] as Map<String, dynamic>?;
    final airingAt = airing?['airingAt'] as int?; // unix SECONDS
    return SeasonalAnime(
      id: id,
      title: name.trim(),
      coverUrl: (cover?['extraLarge'] ?? cover?['large']) as String? ?? '',
      episodes: map['episodes'] as int?,
      status: map['status'] as String? ?? '',
      format: map['format'] as String? ?? '',
      nextEpisode: airing?['episode'] as int?,
      nextAiringAt: airingAt == null ? null : DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
    );
  }
}
