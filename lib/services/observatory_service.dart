import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';

/// One globally-popular anime, straight from AniList.
///
/// [popularity] is AniList's own global figure (users with the media on their
/// list). It has NO geographic dimension — see [ObservatoryService] for why
/// that matters.
class PopularAnime {
  final int id; // anilist_id
  final String title;
  final String coverUrl;

  /// AniList `Media.popularity` — global, unsegmented.
  final int popularity;

  const PopularAnime({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.popularity,
  });
}

/// Per-country member tallies, already reduced to what is safe to render.
///
/// The privacy floor is applied HERE, not in the widget, so no future caller
/// can render a country the floor should have suppressed.
class CountryBreakdown {
  /// Country code → member count, only for countries at or above the floor.
  /// Never contains 'XX'.
  final Map<String, int> visible;

  /// Everyone not in [visible]: below-floor countries, the 'XX' unknown
  /// sentinel, and docs carrying no countryCode at all. Deliberately a single
  /// opaque number — naming the countries inside it would defeat the floor.
  final int otherCount;

  /// Unfiltered `users` total. Authoritative. NOT the sum of the parts —
  /// see [ObservatoryService.fetchCountryBreakdown].
  final int totalMembers;

  const CountryBreakdown({
    required this.visible,
    required this.otherCount,
    required this.totalMembers,
  });

  /// True when no country cleared the floor — the map's empty state.
  /// This is the expected result at current production scale.
  bool get isEmpty => visible.isEmpty;
}

/// Real, sourced numbers for the Observatory screen.
///
/// Every figure this service returns traces to a Firestore aggregation or an
/// AniList field. Nothing is derived, estimated, or invented — the screen this
/// backs previously shipped ten hardcoded figures.
class ObservatoryService {
  ObservatoryService._();
  static final ObservatoryService instance = ObservatoryService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  /// PRIVACY FLOOR — a country with fewer than this many members is never
  /// named or rendered. A country showing "1 member" identifies that person.
  static const int privacyFloor = 5;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[ObservatoryService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[ObservatoryService] $op failed: $e');
      rethrow;
    }
  }

  /// Total members — one unfiltered count() over `users`.
  ///
  /// Deliberately NOT the sum of per-country counts. Firestore equality
  /// filters skip documents missing the field, and production currently has
  /// two user docs with no `countryCode` at all, so summing the parts
  /// under-reports the total (7 vs 9 as of 2026-08-16).
  Future<int> fetchTotalMembers() {
    return _guard('fetchTotalMembers', () async {
      final agg = await _users.count().get();
      final total = agg.count ?? 0;
      debugPrint('[ObservatoryService] users total = $total');
      return total;
    });
  }

  /// Posts created since 00:00 UTC today — one count() with a range filter.
  ///
  /// UTC, not local: `posts.createdAt` is a serverTimestamp and the rules
  /// already treat UTC as the canonical day (see `serverDay()` in
  /// firestore.rules), so a local-midnight boundary would disagree with the
  /// rest of the backend. The UI labels this as a UTC-day figure.
  ///
  /// Posts whose serverTimestamp is still pending resolve to null and are
  /// excluded by the range filter — they are counted once the write lands.
  Future<int> fetchPostsToday() {
    return _guard('fetchPostsToday', () async {
      final now = DateTime.now().toUtc();
      final startOfDay = DateTime.utc(now.year, now.month, now.day);
      final agg = await _db
          .collection('posts')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .count()
          .get();
      final count = agg.count ?? 0;
      debugPrint('[ObservatoryService] posts since ${startOfDay.toIso8601String()} = $count');
      return count;
    });
  }

  /// Per-country member tallies with the privacy floor already applied.
  ///
  /// NOT RENDERED YET — the map is deferred. This exists so the map can drop
  /// onto a floor-enforcing source instead of growing one later.
  ///
  /// TODO(observatory-map): Phase 1 findings that constrain any map built on
  /// this — all four are measured, not assumed:
  ///
  ///  1. Firestore has NO GROUP BY. count()/sum()/avg() cannot group, so the
  ///     distinct country set must be discovered before it can be counted.
  ///     This method reads `users` once to learn the set, then issues one
  ///     count() per discovered code — never a stored counter. The discovery
  ///     read is the scaling limit: it is O(users), fine at 9 and wrong at
  ///     100k. The alternative is ~249 count() calls against a fixed ISO
  ///     3166-1 list, which is O(1) in users but 249 round trips. Revisit
  ///     when the user base makes the tradeoff real.
  ///  2. TWO production docs carry no `countryCode` field at all (backfill
  ///     gap — ensureProfile has not run for those users since it shipped).
  ///     Equality filters never match them, so they are invisible to every
  ///     per-country count. They are folded into [CountryBreakdown.otherCount]
  ///     via the total, never dropped silently.
  ///  3. 'XX' is the UNKNOWN SENTINEL, not a country (FollowService
  ///     .detectCountryCode returns it when the device locale carries no
  ///     region). It must never be given a map fill or a country label.
  ///  4. `countryCode` is alpha-2 in practice but NOT by contract: both the
  ///     client and validCountry() in firestore.rules accept length 2 OR 3,
  ///     so 3-digit UN M.49 region codes (e.g. '419') can be stored. A map
  ///     keyed on ISO alpha-2 must treat non-alpha-2 values as unmappable
  ///     rather than assume they will render.
  Future<CountryBreakdown> fetchCountryBreakdown() {
    return _guard('fetchCountryBreakdown', () async {
      final total = await fetchTotalMembers();

      // Step 1 — discover the distinct country codes. See TODO item 1: there
      // is no GROUP BY, so the set has to be read before it can be counted.
      final snap = await _users.get();
      final codes = <String>{};
      for (final doc in snap.docs) {
        final raw = doc.data()['countryCode'];
        if (raw is! String) continue; // field absent — TODO item 2
        final code = raw.trim().toUpperCase();
        if (code.isEmpty || code == 'XX') continue; // TODO item 3
        codes.add(code);
      }

      // Step 2 — one count() aggregation per discovered code. Authoritative
      // even if the discovery read above is already stale, and never a
      // stored counter.
      final counted = await Future.wait(
        codes.map((code) async {
          final agg = await _users.where('countryCode', isEqualTo: code).count().get();
          return MapEntry(code, agg.count ?? 0);
        }),
      );

      // Step 3 — apply the floor. Below-floor countries are absorbed into
      // "other" WITHOUT being named.
      final visible = <String, int>{};
      var accountedFor = 0;
      for (final entry in counted) {
        accountedFor += entry.value;
        if (entry.value >= privacyFloor) visible[entry.key] = entry.value;
      }

      // Everyone the visible map doesn't name: below-floor countries, 'XX',
      // and the field-absent docs. Derived from the authoritative total so
      // the field-absent docs cannot vanish.
      final visibleTotal = visible.values.fold(0, (acc, n) => acc + n);
      final other = total - visibleTotal;

      debugPrint('[ObservatoryService] countries — discovered ${codes.length}, '
          'above floor ${visible.length}, other $other, total $total '
          '(field-absent: ${total - accountedFor})');

      return CountryBreakdown(
        visible: visible,
        otherCount: other < 0 ? 0 : other,
        totalMembers: total,
      );
    });
  }

  // ── AniList ────────────────────────────────────────────────────────────

  /// Most popular anime GLOBALLY. `popularity` is a single worldwide number
  /// per title with no geographic breakdown available from AniList at all —
  /// it must never tint a map or be presented as a regional figure.
  static const String _popularQuery = r'''
query ($perPage: Int) {
  Page(perPage: $perPage) {
    media(type: ANIME, sort: POPULARITY_DESC, isAdult: false) {
      id
      title { english romaji }
      coverImage { large }
      popularity
    }
  }
}''';

  /// Top [limit] anime by AniList's global popularity. Throws on failure so
  /// the UI can offer Retry.
  Future<List<PopularAnime>> fetchGlobalPopular({int limit = 10}) async {
    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_endpoint),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode(<String, dynamic>{
                'query': _popularQuery,
                'variables': <String, dynamic>{'perPage': limit},
              }),
            )
            .timeout(_timeout),
      );

      if (res.statusCode != 200) {
        debugPrint('[ObservatoryService] AniList FAILED: status ${res.statusCode}\n${res.body}');
        throw HttpException('AniList returned ${res.statusCode}');
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final page = (body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
      final media = page?['media'] as List<dynamic>?;
      if (media == null) throw const FormatException('Unexpected AniList response shape');

      final out = <PopularAnime>[];
      final seen = <int>{};
      for (final raw in media) {
        final m = raw as Map<String, dynamic>;
        final id = m['id'] as int?;
        if (id == null || !seen.add(id)) continue;
        final title = m['title'] as Map<String, dynamic>?;
        final name = (title?['english'] as String?)?.trim().isNotEmpty == true
            ? (title!['english'] as String).trim()
            : (title?['romaji'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        out.add(PopularAnime(
          id: id,
          title: name,
          coverUrl: (m['coverImage'] as Map<String, dynamic>?)?['large'] as String? ?? '',
          // Absent popularity would be a fabricated 0, so drop the row instead.
          popularity: m['popularity'] as int? ?? -1,
        ));
      }
      out.removeWhere((a) => a.popularity < 0);

      debugPrint('[ObservatoryService] fetched ${out.length} globally-popular anime.');
      return out;
    } on SocketException catch (e) {
      debugPrint('[ObservatoryService] socket error: $e');
      rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[ObservatoryService] timeout: $e');
      rethrow;
    }
  }
}
