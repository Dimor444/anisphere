import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';

/// ONE AIRING — a single episode broadcast at a specific time.
///
/// Deliberately not one-per-show. A series that airs twice in the same week
/// produces two entries and correctly appears under both days, which is the
/// whole point of keying off the schedule instead of the media record.
///
/// Referenced by AniList id only — Seasonal is read-only, no Firestore
/// document backs this model.
class AiringEntry {
  final int mediaId; // anilist_id
  final String title; // english ?? romaji
  final String coverUrl;

  /// THIS broadcast's episode number and time — never a show-level
  /// "next episode", which is what used to put shows on the wrong weekday.
  final int episode;
  final DateTime airingAt;

  final int? episodes; // announced total, if known
  final String status; // RELEASING / NOT_YET_RELEASED / … ('' if unknown)
  final String format; // TV / ONA / TV_SHORT / … ('' if unknown)
  final String countryOfOrigin; // JP / CN / KR … ('' if unknown)

  const AiringEntry({
    required this.mediaId,
    required this.title,
    required this.coverUrl,
    required this.episode,
    required this.airingAt,
    required this.episodes,
    required this.status,
    required this.format,
    required this.countryOfOrigin,
  });

  /// Identity of a single broadcast. Two different shows may air at the same
  /// second, and one show may air twice in a week, so all three parts matter.
  String get _slot => '$mediaId/$episode/${airingAt.millisecondsSinceEpoch}';
}

/// Everything airing in a date window, straight from AniList's broadcast
/// schedule.
///
/// Stateless fetcher: the seasonal Riverpod provider is the session cache, so
/// invalidating the provider is what triggers a refetch. Throws on network
/// failure so the UI can show error + retry.
class SeasonalService {
  SeasonalService._();
  static final SeasonalService instance = SeasonalService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  /// AniList's maximum page size.
  static const int _perPage = 50;

  /// Defensive stop. A week measures ~3 pages; anything near this many means
  /// the window or the cursor is wrong, and we would rather render a short
  /// list than hammer a rate-limited API.
  static const int _maxPages = 10;

  /// The schedule, not the season. `season`/`seasonYear` on a Media describe
  /// the PREMIERE season, so a long-runner like ONE PIECE stays tagged
  /// `FALL 1999` forever and no current-season filter can ever match it —
  /// which is why this asks the airing schedule what is actually broadcasting.
  ///
  /// `isAdult` is fetched per-media because `airingSchedules` takes no
  /// isAdult argument: unlike the old `Page.media` query this CANNOT be
  /// filtered server-side, and skipping it ships adult cover art.
  static const String _query = r'''
query ($from: Int, $to: Int, $page: Int, $perPage: Int) {
  Page(page: $page, perPage: $perPage) {
    pageInfo { hasNextPage }
    airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) {
      airingAt
      episode
      media {
        id
        title { romaji english native }
        coverImage { large extraLarge color }
        episodes
        status
        format
        countryOfOrigin
        isAdult
      }
    }
  }
}''';

  /// Every episode airing between [from] (default: now) and 7 days later,
  /// chronologically.
  ///
  /// Pages are walked on `hasNextPage`. `pageInfo.total` is deliberately not
  /// selected: AniList caps it at 5000 regardless of the real count, so a
  /// page count computed from it would be nonsense.
  Future<List<AiringEntry>> fetchWeek({DateTime? from}) async {
    final start = from ?? DateTime.now();
    final end = start.add(const Duration(days: 7));
    final fromSecs = start.millisecondsSinceEpoch ~/ 1000;
    final toSecs = end.millisecondsSinceEpoch ~/ 1000;

    final results = <AiringEntry>[];
    final seen = <String>{};
    var adultDropped = 0;
    var page = 1;
    var requests = 0;

    try {
      while (page <= _maxPages) {
        final body = await _post(fromSecs, toSecs, page);
        requests++;
        final pageData = (body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
        final schedules = pageData?['airingSchedules'] as List<dynamic>?;
        if (schedules == null) throw const FormatException('Unexpected AniList response shape');

        for (final s in schedules) {
          final (entry, wasAdult) = _parseSchedule(s as Map<String, dynamic>);
          if (wasAdult) {
            adultDropped++;
            continue;
          }
          if (entry == null) continue;
          // Guards page boundaries: the underlying schedule can shift between
          // requests, which would otherwise re-deliver a row on the next page.
          if (!seen.add(entry._slot)) continue;
          results.add(entry);
        }

        final hasNext = (pageData?['pageInfo'] as Map<String, dynamic>?)?['hasNextPage'] as bool? ?? false;
        if (!hasNext) break;
        page++;
      }

      results.sort((a, b) => a.airingAt.compareTo(b.airingAt));
      _logComposition(results, requests: requests, adultDropped: adultDropped);
      return results;
    } on SocketException catch (e) {
      debugPrint('[SeasonalService] socket error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[SeasonalService] timeout: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _post(int from, int to, int page) async {
    final res = await AniListRateLimiter.instance.send(
      () => http
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'query': _query,
              'variables': <String, dynamic>{
                'from': from,
                'to': to,
                'page': page,
                'perPage': _perPage,
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
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Schedule row → (entry, wasAdult). Entry is null when the row is
  /// unusable; `wasAdult` is reported separately so the drop can be counted
  /// rather than silently conflated with malformed rows.
  (AiringEntry?, bool) _parseSchedule(Map<String, dynamic> map) {
    final media = map['media'] as Map<String, dynamic>?;
    if (media == null) return (null, false);
    if (media['isAdult'] == true) return (null, true);

    final id = media['id'] as int?;
    final airingAt = map['airingAt'] as int?; // unix SECONDS
    final episode = map['episode'] as int?;
    if (id == null || airingAt == null || episode == null) return (null, false);

    final title = media['title'] as Map<String, dynamic>?;
    final name = (title?['english'] ?? title?['romaji']) as String?;
    if (name == null || name.trim().isEmpty) return (null, false);

    final cover = media['coverImage'] as Map<String, dynamic>?;
    return (
      AiringEntry(
        mediaId: id,
        title: name.trim(),
        coverUrl: (cover?['extraLarge'] ?? cover?['large']) as String? ?? '',
        episode: episode,
        airingAt: DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
        episodes: media['episodes'] as int?,
        status: media['status'] as String? ?? '',
        format: media['format'] as String? ?? '',
        countryOfOrigin: media['countryOfOrigin'] as String? ?? '',
      ),
      false,
    );
  }

  /// Composition breakdown for the UI review: country and format are
  /// deliberately NOT filtered yet, so log what a real week contains before
  /// anyone decides whether to cut CN / ONA / TV_SHORT.
  void _logComposition(List<AiringEntry> rows, {required int requests, required int adultDropped}) {
    if (!kDebugMode) return;
    final byCountry = <String, int>{};
    final byFormat = <String, int>{};
    for (final r in rows) {
      byCountry.update(r.countryOfOrigin, (v) => v + 1, ifAbsent: () => 1);
      byFormat.update(r.format, (v) => v + 1, ifAbsent: () => 1);
    }
    final shows = rows.map((r) => r.mediaId).toSet().length;
    debugPrint('[SeasonalService] ${rows.length} airings / $shows shows '
        'over $requests request(s); dropped $adultDropped adult. '
        'country=$byCountry format=$byFormat');
  }
}
