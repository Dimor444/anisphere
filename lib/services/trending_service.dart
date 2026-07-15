import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anilist_rate_limiter.dart';

/// A single trending anime from AniList.
///
/// The anime is referenced by its AniList id only — no Firestore document
/// backs this model (Trending is a read-only feature).
class TrendingAnime {
  final int id; // anilist_id
  final String title;
  final String coverUrl;
  final String description; // plain text ('' if none)
  final List<String> genres;
  final String status; // RELEASING / FINISHED / … ('' if unknown)
  final double score; // out of 10 (0 if unscored)
  final int? seasonYear;
  final int? nextEpisode; // upcoming episode number
  final DateTime? nextAiringAt; // when that episode airs

  const TrendingAnime({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.description,
    required this.genres,
    required this.status,
    required this.score,
    this.seasonYear,
    this.nextEpisode,
    this.nextAiringAt,
  });

  /// First genre as a short card label ('' if none).
  String get genre => genres.isNotEmpty ? genres.first : '';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'coverUrl': coverUrl,
        'description': description,
        'genres': genres,
        'status': status,
        'score': score,
        'seasonYear': seasonYear,
        'nextEpisode': nextEpisode,
        'nextAiringAt': nextAiringAt?.millisecondsSinceEpoch,
      };

  factory TrendingAnime.fromJson(Map<String, dynamic> json) {
    final airing = json['nextAiringAt'] as int?;
    return TrendingAnime(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      coverUrl: json['coverUrl'] as String? ?? '',
      description: json['description'] as String? ?? '',
      genres: (json['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
      status: json['status'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      seasonYear: json['seasonYear'] as int?,
      nextEpisode: json['nextEpisode'] as int?,
      nextAiringAt: airing == null ? null : DateTime.fromMillisecondsSinceEpoch(airing),
    );
  }
}

/// Live "Trending Now" anime backed by AniList GraphQL.
///
/// Results are cached for 1 hour in SharedPreferences (survives restarts) and
/// mirrored in memory, so the Trending tab can paint cached data instantly
/// while a fresh fetch runs. Failures throw so the UI can show error + retry.
class TrendingService {
  TrendingService._();
  static final TrendingService instance = TrendingService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _ttl = Duration(hours: 1);
  static const String _prefsKey = 'trending_cache_v1';
  static const String _prefsStampKey = 'trending_cache_at_v1';

  // Top 10 trending (currently-airing shows dominate TRENDING_DESC; popularity
  // breaks ties so the list reflects "airing & most popular" right now).
  static const String _query = r'''
query {
  Page(perPage: 10) {
    media(sort: [TRENDING_DESC, POPULARITY_DESC], type: ANIME) {
      id
      title { english romaji }
      coverImage { large }
      description(asHtml: false)
      genres
      status
      averageScore
      seasonYear
      nextAiringEpisode { episode airingAt }
    }
  }
}''';

  // Single-anime lookups (chart taps, deep links) — one query per id per
  // session, on top of whatever the trending list already knows.
  static const String _byIdQuery = r'''
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    id
    title { english romaji }
    coverImage { large }
    description(asHtml: false)
    genres
    status
    averageScore
    seasonYear
    nextAiringEpisode { episode airingAt }
  }
}''';

  final Map<int, TrendingAnime> _byId = {};

  // Free-text search, same field set as trending so results navigate to the
  // detail screen with a complete extra (no follow-up fetch needed).
  static const String _searchQuery = r'''
query ($search: String) {
  Page(page: 1, perPage: 20) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      id
      title { english romaji }
      coverImage { large }
      description(asHtml: false)
      genres
      status
      averageScore
      seasonYear
      nextAiringEpisode { episode airingAt }
    }
  }
}''';

  final Map<String, List<TrendingAnime>> _searchCache = {};

  List<TrendingAnime>? _cache;
  DateTime? _cachedAt;
  bool _prefsLoaded = false;

  bool get _fresh => _cache != null && _cachedAt != null && DateTime.now().difference(_cachedAt!) < _ttl;

  /// Cached list (fresh or stale), or null if nothing has ever been fetched.
  /// Use this to paint the screen immediately while [fetchTrending] runs.
  Future<List<TrendingAnime>?> cached() async {
    await _loadPrefsCache();
    return _cache;
  }

  /// Returns the trending list. Served from the 1-hour cache when fresh
  /// (unless [forceRefresh]); otherwise fetched from AniList. Throws on failure.
  Future<List<TrendingAnime>> fetchTrending({bool forceRefresh = false}) async {
    await _loadPrefsCache();
    if (!forceRefresh && _fresh) return _cache!;

    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_endpoint),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode(<String, dynamic>{'query': _query}),
            )
            .timeout(_timeout),
        priority: true,
      );

      if (res.statusCode != 200) {
        debugPrint('[TrendingService] AniList request FAILED: status ${res.statusCode}\n${res.body}');
        throw HttpException('AniList returned ${res.statusCode}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final page = (body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
      final media = page?['media'] as List<dynamic>?;
      if (media == null) throw const FormatException('Unexpected AniList response shape');

      final results = <TrendingAnime>[];
      final seen = <int>{};
      for (final m in media) {
        final anime = _parseMedia(m as Map<String, dynamic>);
        if (anime == null || !seen.add(anime.id)) continue;
        if (anime.coverUrl.isEmpty) continue; // trending cards need a cover
        results.add(anime);
      }

      debugPrint('[TrendingService] fetched ${results.length} trending anime.');
      _cache = results;
      _cachedAt = DateTime.now();
      unawaited(_persist(results, _cachedAt!));
      return results;
    } on SocketException catch (e) {
      debugPrint('[TrendingService] socket error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[TrendingService] timeout: $e');
      rethrow;
    }
  }

  /// One anime by anilist_id — for chart taps and deep links, where the id
  /// is usually NOT in the trending window. Checks the session cache and the
  /// trending list first, then asks AniList directly.
  ///
  /// Returns null when AniList doesn't know the id (genuine not-found);
  /// throws on network failure so the UI can offer Retry.
  Future<TrendingAnime?> fetchById(int anilistId) async {
    final hit = _byId[anilistId];
    if (hit != null) return hit;
    await _loadPrefsCache();
    final inTrending = _cache?.where((a) => a.id == anilistId) ?? const Iterable<TrendingAnime>.empty();
    if (inTrending.isNotEmpty) return inTrending.first;

    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_endpoint),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode(<String, dynamic>{
                'query': _byIdQuery,
                'variables': <String, dynamic>{'id': anilistId},
              }),
            )
            .timeout(_timeout),
        priority: true,
      );

      if (res.statusCode == 404) return null; // AniList: unknown id
      if (res.statusCode != 200) {
        debugPrint('[TrendingService] fetchById($anilistId) FAILED: status ${res.statusCode}\n${res.body}');
        throw HttpException('AniList returned ${res.statusCode}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final media = (body['data'] as Map<String, dynamic>?)?['Media'] as Map<String, dynamic>?;
      if (media == null) return null;

      final anime = _parseMedia(media);
      if (anime != null) _byId[anilistId] = anime;
      return anime;
    } on SocketException catch (e) {
      debugPrint('[TrendingService] fetchById($anilistId) socket error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[TrendingService] fetchById($anilistId) timeout: $e');
      rethrow;
    }
  }

  /// Free-text anime search (Discover's Search tab). Cached per query for
  /// the session. Throws on network failure; empty list = genuinely no match.
  Future<List<TrendingAnime>> searchAnime(String query) async {
    final key = query.trim().toLowerCase();
    if (key.isEmpty) return const [];
    final hit = _searchCache[key];
    if (hit != null) return hit;

    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_endpoint),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode(<String, dynamic>{
                'query': _searchQuery,
                'variables': <String, dynamic>{'search': query.trim()},
              }),
            )
            .timeout(_timeout),
        priority: true, // user is typing and waiting
      );

      if (res.statusCode != 200) {
        debugPrint('[TrendingService] search("$query") FAILED: status ${res.statusCode}\n${res.body}');
        throw HttpException('AniList returned ${res.statusCode}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final media = ((body['data'] as Map<String, dynamic>?)?['Page']
          as Map<String, dynamic>?)?['media'] as List<dynamic>?;
      if (media == null) throw const FormatException('Unexpected AniList response shape');

      final results = <TrendingAnime>[];
      final seen = <int>{};
      for (final m in media) {
        final anime = _parseMedia(m as Map<String, dynamic>);
        if (anime == null || !seen.add(anime.id)) continue;
        results.add(anime);
        _byId[anime.id] = anime; // detail screen reuses these for free
      }
      return _searchCache[key] = results;
    } on SocketException catch (e) {
      debugPrint('[TrendingService] search("$query") socket error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[TrendingService] search("$query") timeout: $e');
      rethrow;
    }
  }

  /// AniList media map → model. Null when id/title are unusable.
  TrendingAnime? _parseMedia(Map<String, dynamic> map) {
    final id = map['id'] as int?;
    if (id == null) return null;
    final title = map['title'] as Map<String, dynamic>?;
    final name = (title?['english'] ?? title?['romaji']) as String?;
    if (name == null || name.trim().isEmpty) return null;

    final s = map['averageScore'];
    final airing = map['nextAiringEpisode'] as Map<String, dynamic>?;
    final airingAt = airing?['airingAt'] as int?;
    return TrendingAnime(
      id: id,
      title: name.trim(),
      coverUrl: (map['coverImage'] as Map<String, dynamic>?)?['large'] as String? ?? '',
      description: _stripHtml(map['description'] as String? ?? ''),
      genres: (map['genres'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
      status: map['status'] as String? ?? '',
      score: s is num ? s / 10.0 : 0.0,
      seasonYear: map['seasonYear'] as int?,
      nextEpisode: airing?['episode'] as int?,
      nextAiringAt: airingAt == null ? null : DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
    );
  }

  // ── SharedPreferences cache ────────────────────────────────────────────

  Future<void> _loadPrefsCache() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      final stamp = prefs.getInt(_prefsStampKey);
      if (raw == null || stamp == null) return;

      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => TrendingAnime.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isEmpty) return;
      // Only adopt if newer than what's already in memory.
      final at = DateTime.fromMillisecondsSinceEpoch(stamp);
      if (_cachedAt == null || at.isAfter(_cachedAt!)) {
        _cache = list;
        _cachedAt = at;
      }
    } catch (e) {
      debugPrint('[TrendingService] failed to read prefs cache: $e');
    }
  }

  Future<void> _persist(List<TrendingAnime> list, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(list.map((a) => a.toJson()).toList()));
      await prefs.setInt(_prefsStampKey, at.millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[TrendingService] failed to persist cache: $e');
    }
  }

  /// AniList descriptions arrive with light HTML (<br>, <i>, …) even with
  /// asHtml:false — flatten to plain text for Text widgets.
  static String _stripHtml(String html) {
    if (html.isEmpty) return '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
