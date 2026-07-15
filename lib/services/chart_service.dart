import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'anilist_rate_limiter.dart';

/// Which slice of the Top 100 chart to show.
enum ChartFilter {
  allTime('All Time'),
  season('Season'),
  year('Year');

  final String label;
  const ChartFilter(this.label);
}

/// One ranked row of the Top 100.
class AnimeChartEntry {
  final int rank; // 1-based
  final int anilistId;
  final String title;
  final String coverImage;
  final double score; // out of 10
  final int ratings; // AniList popularity (list count)

  /// Rank change vs the previous (different-day) snapshot: positive = climbed,
  /// negative = dropped, 0 = unchanged or no history yet.
  final int movement;

  const AnimeChartEntry({
    required this.rank,
    required this.anilistId,
    required this.title,
    required this.coverImage,
    required this.score,
    required this.ratings,
    this.movement = 0,
  });

  factory AnimeChartEntry.fromMedia(Map<String, dynamic> m, int rank) {
    final title = m['title'] as Map<String, dynamic>?;
    final cover = m['coverImage'] as Map<String, dynamic>?;
    final avg = m['averageScore'];
    return AnimeChartEntry(
      rank: rank,
      anilistId: (m['id'] as num?)?.toInt() ?? 0,
      title: (title?['english'] ?? title?['romaji']) as String? ?? '?',
      coverImage: cover?['large'] as String? ?? '',
      score: avg is num ? avg / 10.0 : 0.0,
      ratings: (m['popularity'] as num?)?.toInt() ?? 0,
    );
  }

  AnimeChartEntry withMovement(int m) => AnimeChartEntry(
        rank: rank,
        anilistId: anilistId,
        title: title,
        coverImage: coverImage,
        score: score,
        ratings: ratings,
        movement: m,
      );
}

/// AniList-backed Top 100 chart with three genuinely different slices:
/// all-time best, current season, current year (each sorted SCORE_DESC).
///
/// AniList caps perPage at 50, so a chart is two paginated calls stitched
/// together. Each filter caches independently for [cacheTtl]; the UI reads
/// [cached] for an instant paint and awaits [getTopAnime] for freshness.
///
/// Rank movement (^3 / v1 / –) compares against the last snapshot taken on a
/// previous day, persisted in SharedPreferences per filter — no fake data:
/// with no history everything shows "–".
class ChartService {
  ChartService._();
  static final ChartService instance = ChartService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const int topCount = 100;
  static const int _perPage = 50;
  static const Duration cacheTtl = Duration(hours: 1);
  static const Duration _timeout = Duration(seconds: 12);

  final Map<ChartFilter, List<AnimeChartEntry>> _cache = {};
  final Map<ChartFilter, DateTime> _cachedAt = {};

  /// (season, year) for [now] — Winter Jan–Mar, Spring Apr–Jun,
  /// Summer Jul–Sep, Fall Oct–Dec.
  static ({String season, int year}) currentSeason(DateTime now) {
    final season = switch (now.month) {
      >= 1 && <= 3 => 'WINTER',
      >= 4 && <= 6 => 'SPRING',
      >= 7 && <= 9 => 'SUMMER',
      _ => 'FALL',
    };
    return (season: season, year: now.year);
  }

  /// Movement per anilistId: previousRank - currentRank (missing → 0).
  @visibleForTesting
  static Map<int, int> computeMovements(Map<int, int> current, Map<int, int> previous) {
    return current.map((id, rank) {
      final prev = previous[id];
      return MapEntry(id, prev == null ? 0 : prev - rank);
    });
  }

  /// Last fetched list for [filter] — possibly stale, null if never loaded.
  /// Paint this immediately, then await [getTopAnime].
  List<AnimeChartEntry>? cached(ChartFilter filter) => _cache[filter];

  /// The Top 100 for [filter]; served from cache within [cacheTtl].
  Future<List<AnimeChartEntry>> getTopAnime(ChartFilter filter) async {
    final at = _cachedAt[filter];
    final hit = _cache[filter];
    if (hit != null && at != null && DateTime.now().difference(at) < cacheTtl) {
      return hit;
    }

    final pages = <List<AnimeChartEntry>>[];
    for (var page = 1; pages.length * _perPage < topCount; page++) {
      final offset = pages.fold(0, (n, p) => n + p.length);
      final batch = await _fetchPage(filter, page, offset);
      pages.add(batch);
      if (batch.length < _perPage) break; // AniList ran out (short seasons)
    }
    final entries = pages.expand((p) => p).toList();

    final ranked = await _applyMovements(filter, entries);
    _cache[filter] = ranked;
    _cachedAt[filter] = DateTime.now();
    return ranked;
  }

  Future<List<AnimeChartEntry>> _fetchPage(ChartFilter filter, int page, int rankOffset) async {
    final s = currentSeason(DateTime.now());
    final args = switch (filter) {
      ChartFilter.allTime => 'type: ANIME, sort: SCORE_DESC',
      ChartFilter.season =>
        'type: ANIME, season: ${s.season}, seasonYear: ${s.year}, sort: SCORE_DESC',
      ChartFilter.year => 'type: ANIME, seasonYear: ${s.year}, sort: SCORE_DESC',
    };
    final query = '''
query {
  Page(page: $page, perPage: $_perPage) {
    media($args) {
      id
      title { romaji english }
      coverImage { large }
      averageScore
      popularity
      favourites
    }
  }
}''';

    final res = await AniListRateLimiter.instance.send(
      () => http
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'query': query}),
          )
          .timeout(_timeout),
      priority: true, // user is staring at the chart
    );
    if (res.statusCode != 200) {
      debugPrint('[ChartService] ${filter.name} page $page failed: ${res.statusCode}\n${res.body}');
      throw http.ClientException('AniList ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final media =
        ((body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?)?['media']
            as List<dynamic>?;
    if (media == null) throw const FormatException('AniList: no media in response');

    return [
      for (var i = 0; i < media.length; i++)
        AnimeChartEntry.fromMedia(media[i] as Map<String, dynamic>, rankOffset + i + 1),
    ];
  }

  // ── Movement history (SharedPreferences) ───────────────────────────────

  String _snapKey(ChartFilter f) => 'chart_snapshot_${f.name}';
  String _prevKey(ChartFilter f) => 'chart_snapshot_prev_${f.name}';

  /// Compare against the newest snapshot from a *previous* day, rolling
  /// snapshots forward at most once per day so intra-day refreshes don't
  /// zero the indicators.
  Future<List<AnimeChartEntry>> _applyMovements(
      ChartFilter filter, List<AnimeChartEntry> entries) async {
    final current = {for (final e in entries) e.anilistId: e.rank};
    Map<int, int> previous = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10);

      final stored = _decodeSnap(prefs.getString(_snapKey(filter)));
      if (stored == null) {
        await prefs.setString(_snapKey(filter), _encodeSnap(today, current));
      } else if (stored.date != today) {
        await prefs.setString(_prevKey(filter), _encodeSnap(stored.date, stored.ranks));
        await prefs.setString(_snapKey(filter), _encodeSnap(today, current));
        previous = stored.ranks;
      } else {
        previous = _decodeSnap(prefs.getString(_prevKey(filter)))?.ranks ?? const {};
      }
    } catch (e) {
      debugPrint('[ChartService] movement history failed: $e'); // chart still renders, just with "–"
    }

    final moves = computeMovements(current, previous);
    return [for (final e in entries) e.withMovement(moves[e.anilistId] ?? 0)];
  }

  String _encodeSnap(String date, Map<int, int> ranks) =>
      jsonEncode({'date': date, 'ranks': ranks.map((k, v) => MapEntry('$k', v))});

  ({String date, Map<int, int> ranks})? _decodeSnap(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final ranks = (map['ranks'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(int.parse(k), (v as num).toInt()));
      return (date: map['date'] as String, ranks: ranks);
    } catch (_) {
      return null;
    }
  }
}
