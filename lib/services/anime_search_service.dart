import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';

/// One anime returned by a search — enough to render a selectable card and to
/// start a challenge.
class AnimeSearchResult {
  final String title;
  final String genre;
  final double rating; // out of 10
  final int anilistId; // 0 when unknown
  final String coverImage;
  const AnimeSearchResult({
    required this.title,
    required this.genre,
    required this.rating,
    this.anilistId = 0,
    this.coverImage = '',
  });
}

/// Free-text anime search backed by AniList GraphQL (https://graphql.anilist.co),
/// so the True Fan picker can find ANY anime, not just the preset list.
///
/// Results are cached per query string. Any failure resolves to an empty list.
class AnimeSearchService {
  AnimeSearchService._();

  /// Shared singleton so the cache is reused across the app.
  static final AnimeSearchService instance = AnimeSearchService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  static const String _query = r'''
query ($search: String) {
  Page(perPage: 24) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      id
      title { romaji english }
      genres
      averageScore
      coverImage { large }
    }
  }
}''';

  final Map<String, List<AnimeSearchResult>> _cache = <String, List<AnimeSearchResult>>{};

  /// Returns anime matching [query], or an empty list on failure.
  Future<List<AnimeSearchResult>> searchAnime(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return const [];

    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      // High priority — user is actively waiting on search results.
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_endpoint),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(<String, dynamic>{
                'query': _query,
                'variables': <String, dynamic>{'search': query},
              }),
            )
            .timeout(_timeout),
        priority: true,
      );

      if (res.statusCode != 200) {
        debugPrint('[AnimeSearchService] AniList request FAILED for "$query": '
            'status ${res.statusCode}\n${res.body}');
        return const []; // transient — don't cache
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final page = (body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
      final media = page?['media'] as List<dynamic>?;
      if (media == null) return _cache[key] = const [];

      final results = <AnimeSearchResult>[];
      final seen = <String>{};
      for (final m in media) {
        final map = m as Map<String, dynamic>;
        final title = map['title'] as Map<String, dynamic>?;
        final name = (title?['english'] ?? title?['romaji']) as String?;
        if (name == null || name.trim().isEmpty) continue;
        if (!seen.add(name.trim().toLowerCase())) continue; // de-dupe

        final genres = (map['genres'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
        final score = map['averageScore'];
        final rating = score is num ? score / 10.0 : 0.0;

        results.add(AnimeSearchResult(
          title: name.trim(),
          genre: genres.isNotEmpty ? genres.first : '',
          rating: rating.toDouble(),
          anilistId: (map['id'] as num?)?.toInt() ?? 0,
          coverImage: ((map['coverImage'] as Map<String, dynamic>?)?['large'] as String?) ?? '',
        ));
      }

      debugPrint('[AnimeSearchService] "$query" → ${results.length} results.');
      return _cache[key] = results;
    } on SocketException catch (e) {
      debugPrint('[AnimeSearchService] socket error for "$query": $e');
      return const [];
    } on TimeoutException catch (e) {
      debugPrint('[AnimeSearchService] timeout for "$query": $e');
      return const [];
    } catch (e, st) {
      debugPrint('[AnimeSearchService] EXCEPTION for "$query": $e\n$st');
      return const [];
    }
  }
}
