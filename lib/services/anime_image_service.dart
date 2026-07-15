import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';
import 'title_match.dart';

/// Outcome of an image lookup, so the UI can tell apart "no image found"
/// (show the letter fallback) from "the device is offline" (show a wifi-off
/// icon and let the user retry).
enum ImageFetchStatus { found, notFound, offline }

class AnimeImageResult {
  final String? url;
  final ImageFetchStatus status;
  const AnimeImageResult(this.status, [this.url]);

  static const AnimeImageResult notFound = AnimeImageResult(ImageFetchStatus.notFound);
  static const AnimeImageResult offline = AnimeImageResult(ImageFetchStatus.offline);
}

/// Internal per-source result. [errored] is `true` for transient failures
/// (non-200 responses, timeouts, socket errors) so the caller knows the miss
/// is worth retrying and must NOT be cached.
class _SourceResult {
  final String? url;
  final bool errored;
  const _SourceResult({this.url, this.errored = false});
}

/// Resolves anime cover images, primarily from the Jikan REST API
/// (https://api.jikan.moe/v4) and, when that fails, from the AniList GraphQL
/// API (https://graphql.anilist.co).
///
/// Successful URLs and *definitive* misses (the API answered, but had no match)
/// are memoised in a [Map] so we never re-request them. Transient failures
/// (rate limits, timeouts, offline) are deliberately NOT cached, so a retry can
/// actually fetch the image once connectivity/limits recover.
class AnimeImageService {
  AnimeImageService._();

  /// Shared singleton so the cache is reused across every card on screen.
  static final AnimeImageService instance = AnimeImageService._();

  static const String _jikanBase = 'https://api.jikan.moe/v4';
  static const String _aniListEndpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  /// title (lower-cased) -> cover image URL, or `null` for a definitive miss.
  final Map<String, String?> _cache = <String, String?>{};

  /// Resolves the best cover image for [animeName].
  ///
  /// Tries AniList first (primary — more reliable), then Jikan as a last-resort
  /// fallback. Cached successes/definitive-misses resolve instantly. Returns
  /// [ImageFetchStatus.offline] when both sources fail and a connectivity check
  /// confirms there is no internet.
  /// Set [priority] for gameplay-critical covers (e.g. the result card) so they
  /// jump ahead of the low-priority cover-grid thumbnails under the AniList rate
  /// limit.
  Future<AnimeImageResult> fetchImage(String animeName, {bool priority = false}) async {
    final key = animeName.trim().toLowerCase();
    if (key.isEmpty) return AnimeImageResult.notFound;

    // Cache hit: a stored URL is a hit; a stored null is a definitive miss.
    if (_cache.containsKey(key)) {
      final cached = _cache[key];
      return AnimeImageResult(
        cached != null ? ImageFetchStatus.found : ImageFetchStatus.notFound,
        cached,
      );
    }

    var transient = false;

    // 1) AniList (primary)
    final aniList = await _fetchFromAniList(animeName, priority: priority);
    if (aniList.url != null) {
      _cache[key] = aniList.url;
      return AnimeImageResult(ImageFetchStatus.found, aniList.url);
    }
    transient |= aniList.errored;

    // 2) Jikan (last-resort fallback)
    final jikan = await _fetchFromJikan(animeName);
    if (jikan.url != null) {
      _cache[key] = jikan.url;
      return AnimeImageResult(ImageFetchStatus.found, jikan.url);
    }
    transient |= jikan.errored;

    // 3) Both failed. Distinguish "offline" from "genuinely no image".
    if (!await hasInternet()) {
      debugPrint('[AnimeImageService] No internet — offline fallback for "$animeName".');
      return AnimeImageResult.offline; // not cached: retry once back online
    }

    if (transient) {
      // Online, but a source errored (5xx, timeout, etc.). Don't cache so the
      // retry button can try again.
      debugPrint('[AnimeImageService] Transient failure for "$animeName" — not caching.');
      return AnimeImageResult.notFound;
    }

    // Both APIs answered but had no match — a real miss; cache it.
    debugPrint('[AnimeImageService] No image found for "$animeName" on AniList or Jikan.');
    _cache[key] = null;
    return AnimeImageResult.notFound;
  }

  /// Lightweight connectivity check via a DNS lookup of the AniList host.
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('graphql.anilist.co').timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    }
  }

  /// Last-resort fallback. Pulls several results (not just the top one) so we
  /// can skip any whose title doesn't actually match the requested anime.
  Future<_SourceResult> _fetchFromJikan(String animeName) async {
    try {
      final uri = Uri.parse('$_jikanBase/anime').replace(queryParameters: <String, String>{
        'q': animeName,
        'limit': '8',
        'sfw': 'true',
      });

      final res = await http.get(uri).timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('[AnimeImageService] Jikan request FAILED for "$animeName"\n'
            '  GET $uri\n'
            '  status: ${res.statusCode} ${res.reasonPhrase}\n'
            '  body: ${res.body}');
        return const _SourceResult(errored: true);
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = body['data'] as List<dynamic>?;
      if (data == null || data.isEmpty) {
        return const _SourceResult(); // definitive miss
      }

      // Walk results in relevance order; use the first whose title matches and
      // has an image. Skipping mismatches avoids "wrong anime" covers.
      for (final item in data) {
        final anime = item as Map<String, dynamic>;
        if (!jikanResultMatches(animeName, anime)) continue;

        final images = anime['images'] as Map<String, dynamic>?;
        final jpg = images?['jpg'] as Map<String, dynamic>?;
        final url = (jpg?['large_image_url'] ?? jpg?['image_url']) as String?;
        if (url != null && url.isNotEmpty) {
          return _SourceResult(url: url);
        }
      }

      debugPrint('[AnimeImageService] Jikan: no title match for "$animeName" '
          'among ${data.length} results — falling through.');
      return const _SourceResult(); // no trustworthy match → fallback / AniList
    } catch (e, st) {
      debugPrint('[AnimeImageService] Jikan EXCEPTION for "$animeName": $e\n$st');
      return const _SourceResult(errored: true);
    }
  }

  /// Primary source — AniList GraphQL. AniList's search ranks the correct anime
  /// first, so we trust the top result and use its cover directly (no title
  /// matching — that only produced false "no match" letters).
  Future<_SourceResult> _fetchFromAniList(String animeName, {bool priority = false}) async {
    const query = r'''
query ($search: String) {
  Media(search: $search, type: ANIME) {
    coverImage { large }
  }
}''';
    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
          .post(
            Uri.parse(_aniListEndpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'query': query,
              'variables': <String, dynamic>{'search': animeName},
            }),
          )
          .timeout(_timeout),
        priority: priority,
      );

      if (res.statusCode != 200) {
        debugPrint('[AnimeImageService] AniList request FAILED for "$animeName"\n'
            '  POST $_aniListEndpoint\n'
            '  status: ${res.statusCode} ${res.reasonPhrase}\n'
            '  body: ${res.body}');
        return const _SourceResult(errored: true);
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final media = (body['data'] as Map<String, dynamic>?)?['Media'] as Map<String, dynamic>?;
      if (media == null) return const _SourceResult();

      // Trust AniList's top result — just take its cover image.
      final cover = media['coverImage'] as Map<String, dynamic>?;
      final url = cover?['large'] as String?;
      return _SourceResult(url: (url != null && url.isNotEmpty) ? url : null);
    } catch (e, st) {
      debugPrint('[AnimeImageService] AniList EXCEPTION for "$animeName": $e\n$st');
      return const _SourceResult(errored: true);
    }
  }
}
