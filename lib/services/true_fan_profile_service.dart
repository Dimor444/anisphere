import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';
import 'auth_service.dart';
import 'true_fan_score_service.dart';

/// One anime the signed-in user holds a True Fan pass on, with their exact
/// global rank on that anime's leaderboard.
class TrueFanProfileEntry {
  final int anilistId;
  final String title;

  /// AniList cover URL — empty when AniList had no match or was unreachable
  /// (the card falls back to a gradient).
  final String coverUrl;

  /// Global rank, 1-based: strictly-faster passed runs + 1.
  final int rank;
  final double timeSeconds;

  /// Owner chose to hide this title from their public profile. Display-only:
  /// the score still counts on the anime's leaderboard. Missing on older
  /// docs → false.
  final bool hidden;

  const TrueFanProfileEntry({
    required this.anilistId,
    required this.title,
    required this.coverUrl,
    required this.rank,
    required this.timeSeconds,
    this.hidden = false,
  });
}

/// Read-only view of the signed-in user's True Fan passes for the profile
/// screen: their own passed `trueFanScores` docs, each with a live global
/// rank from the same count() aggregation the leaderboard uses. Never writes
/// to Firestore, and anime metadata (title/cover) comes from AniList at read
/// time — it is never stored.
class TrueFanProfileService {
  TrueFanProfileService._();
  static final TrueFanProfileService instance = TrueFanProfileService._();

  static const String _aniListEndpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  /// AniList caps Page.perPage at 50 — ids are batch-fetched in pages of this.
  static const int _metadataPageSize = 50;

  /// At most this many rank count() aggregations in flight at once, so a
  /// profile with many passes doesn't fire an unbounded query burst.
  static const int _rankConcurrency = 5;

  /// anilistId -> resolved metadata, memoised for the app session.
  final Map<int, ({String title, String cover})> _metaCache = {};

  /// All animes the signed-in user passed — hidden ones included, each
  /// carrying its [TrueFanProfileEntry.hidden] flag so the owner's profile
  /// can mark them. Sorted by global rank (best first).
  ///
  /// Ranks reuse [TrueFanScoreService.rankForTime]; titles/covers come from a
  /// single batched AniList `id_in` query, falling back to the doc's
  /// denormalized `animeTitle` when AniList can't resolve an id.
  Future<List<TrueFanProfileEntry>> fetchMyEntries() async {
    final uid = (await AuthService.instance.initAuth()).uid;
    return _fetchEntries(uid, includeHidden: true);
  }

  /// The PUBLIC view of [uid]'s passes: entries the owner hid are filtered
  /// out (before rank aggregation, so hidden titles cost no queries).
  Future<List<TrueFanProfileEntry>> fetchVisibleEntriesFor(String uid) {
    return _fetchEntries(uid, includeHidden: false);
  }

  Future<List<TrueFanProfileEntry>> _fetchEntries(String uid, {required bool includeHidden}) async {
    try {
      // Equality-only query — served by Firestore's single-field index
      // merging, so no composite index is required.
      final snap = await FirebaseFirestore.instance
          .collection('trueFanScores')
          .where('userId', isEqualTo: uid)
          .where('passed', isEqualTo: true)
          .get();

      final passes = <({int anilistId, String docTitle, double timeSeconds, bool hidden})>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final anilistId = (d['anilistId'] as num?)?.toInt() ?? 0;
        final timeSeconds = (d['timeSeconds'] as num?)?.toDouble() ?? 0;
        if (anilistId <= 0 || timeSeconds <= 0) continue;
        // Missing on docs written before the toggle existed → visible.
        final hidden = d['hiddenFromProfile'] == true;
        if (hidden && !includeHidden) continue;
        passes.add((
          anilistId: anilistId,
          docTitle: d['animeTitle'] as String? ?? '',
          timeSeconds: timeSeconds,
          hidden: hidden,
        ));
      }
      if (passes.isEmpty) return const [];

      // Global ranks via count() aggregations, capped concurrency.
      final ranks = <int, int>{};
      for (var i = 0; i < passes.length; i += _rankConcurrency) {
        final chunk = passes.sublist(i, min(i + _rankConcurrency, passes.length));
        await Future.wait(chunk.map((p) async {
          ranks[p.anilistId] =
              await TrueFanScoreService.instance.rankForTime(p.anilistId, p.timeSeconds);
        }));
      }

      await _fetchMetadata(passes.map((p) => p.anilistId).toList());

      final entries = passes.map((p) {
        final meta = _metaCache[p.anilistId];
        return TrueFanProfileEntry(
          anilistId: p.anilistId,
          title: (meta?.title.isNotEmpty ?? false) ? meta!.title : p.docTitle,
          coverUrl: meta?.cover ?? '',
          rank: ranks[p.anilistId] ?? 1,
          timeSeconds: p.timeSeconds,
          hidden: p.hidden,
        );
      }).toList()
        ..sort((a, b) {
          final byRank = a.rank.compareTo(b.rank);
          if (byRank != 0) return byRank;
          final byTime = a.timeSeconds.compareTo(b.timeSeconds);
          return byTime != 0 ? byTime : a.title.compareTo(b.title);
        });
      return entries;
    } on FirebaseException catch (e) {
      debugPrint('[TrueFanProfileService] _fetchEntries failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[TrueFanProfileService] _fetchEntries failed: $e');
      rethrow;
    }
  }

  /// Hide or unhide one of the signed-in user's own passes on their public
  /// profile. Sends ONLY `hiddenFromProfile` (merge) — every score field
  /// stays client-immutable, enforced by the rules' hide-toggle branch.
  /// Throws on failure so the UI can revert its optimistic toggle.
  Future<void> setHidden({required int anilistId, required bool hidden}) async {
    final uid = (await AuthService.instance.initAuth()).uid;
    try {
      await FirebaseFirestore.instance
          .collection('trueFanScores')
          .doc('${uid}_$anilistId')
          .set(<String, dynamic>{'hiddenFromProfile': hidden}, SetOptions(merge: true));
      debugPrint('[TrueFanProfileService] set hiddenFromProfile=$hidden for anime $anilistId.');
    } on FirebaseException catch (e) {
      debugPrint('[TrueFanProfileService] setHidden($anilistId) failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[TrueFanProfileService] setHidden($anilistId) failed: $e');
      rethrow;
    }
  }

  /// Resolves title + cover for [ids] from AniList in `id_in` pages, filling
  /// [_metaCache]. Failures only log — callers fall back to the doc title.
  Future<void> _fetchMetadata(List<int> ids) async {
    const query = r'''
query ($ids: [Int]) {
  Page(perPage: 50) {
    media(id_in: $ids, type: ANIME) {
      id
      title { english romaji }
      coverImage { large }
    }
  }
}''';
    final missing = ids.where((id) => !_metaCache.containsKey(id)).toList();
    for (var i = 0; i < missing.length; i += _metadataPageSize) {
      final page = missing.sublist(i, min(i + _metadataPageSize, missing.length));
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
                  'variables': <String, dynamic>{'ids': page},
                }),
              )
              .timeout(_timeout),
          priority: true,
        );
        if (res.statusCode != 200) {
          debugPrint('[TrueFanProfileService] AniList batch FAILED: '
              'status ${res.statusCode}\n${res.body}');
          continue;
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final pageData = (body['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
        final media = pageData?['media'] as List<dynamic>? ?? const [];
        for (final m in media) {
          final map = m as Map<String, dynamic>;
          final id = (map['id'] as num?)?.toInt();
          if (id == null) continue;
          final title = map['title'] as Map<String, dynamic>?;
          _metaCache[id] = (
            title: ((title?['english'] ?? title?['romaji']) as String?)?.trim() ?? '',
            cover: ((map['coverImage'] as Map<String, dynamic>?)?['large'] as String?) ?? '',
          );
        }
      } catch (e) {
        debugPrint('[TrueFanProfileService] AniList batch EXCEPTION: $e');
      }
    }
  }
}
