import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models/user.dart';
import 'anilist_rate_limiter.dart';
import 'auth_service.dart';
import 'my_list_service.dart';

/// AniList metadata for one DNA slot — fetched live by id, never persisted
/// (Firestore stores anilistId ints only; titles/covers/genres always come
/// from AniList at render time, same scheme as the story anime tag).
class DnaAnime {
  final int anilistId;
  final String title;
  final String coverUrl;
  final int? seasonYear;
  final List<String> genres;

  /// AniList community score out of 10 (0 when unscored).
  final double communityScore;

  const DnaAnime({
    required this.anilistId,
    required this.title,
    required this.coverUrl,
    required this.seasonYear,
    required this.genres,
    required this.communityScore,
  });
}

/// One rendered DNA card.
class AnimeDnaCard {
  final DnaAnime anime;

  /// The owner's own rating (0–10) when the anime is in their list and rated.
  final double? userScore;

  /// True when this slot comes from `dnaPinned` rather than derivation.
  final bool pinned;

  const AnimeDnaCard({required this.anime, this.userScore, required this.pinned});

  /// Score shown on the card badge: the user's own rating when they rated
  /// the anime, else the AniList community score. 0 renders no badge.
  double get displayScore => userScore ?? anime.communityScore;
}

/// A user's computed Anime DNA: top cards, genre fingerprint, first anime.
class AnimeDna {
  final List<AnimeDnaCard> cards;
  final List<String> topGenres;

  /// Resolved `firstAnimeId` — null when unset or AniList can't resolve it.
  final DnaAnime? firstAnime;

  /// myList entries the derivation saw (0 for another user's profile, whose
  /// list is not client-readable under current rules).
  final int listSize;

  const AnimeDna({
    required this.cards,
    required this.topGenres,
    required this.firstAnime,
    required this.listSize,
  });

  bool get isEmpty => cards.isEmpty && topGenres.isEmpty && firstAnime == null;
}

/// Anime DNA — the profile's taste fingerprint, derived from the user's own
/// My List (`users/{uid}/myList`) with owner overrides on the user doc:
///
///  - `dnaPinned`  (max [UserData.maxDnaPinned] anilistIds) fills card slots
///    first, in stored order; derivation fills the remainder.
///  - `firstAnimeId` is always user-entered — it cannot be derived.
///
/// Derivation ranks list entries by the user's own `score` (highest first,
/// unrated last), tie-broken by `addedAt` ascending (the longest-listed anime
/// wins), then `anilistId` ascending for determinism.
///
/// All AniList metadata resolves through ONE batched `id_in` query per render
/// (pages of 50, session-cached), mirroring TrueFanProfileService.
class AnimeDnaService {
  AnimeDnaService._();
  static final AnimeDnaService instance = AnimeDnaService._();

  static const String _endpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  /// Cards shown on the profile rail.
  static const int cardCap = 5;

  /// Genre pills shown under the rail.
  static const int genreCap = 5;

  /// AniList caps Page.perPage at 50.
  static const int _metaPageSize = 50;

  /// anilistId -> resolved metadata, memoised for the app session.
  final Map<int, DnaAnime> _metaCache = {};

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  // ── Derivation (pure — unit-tested) ─────────────────────────────────────

  /// Card slots for the rail: pinned ids first (stored order, deduped,
  /// capped), then list-derived ids ranked by user score DESC with unrated
  /// entries last. Ties break by addedAt ASC (earliest added wins — a null
  /// addedAt is a just-written entry and sorts newest), then anilistId ASC.
  static List<int> deriveCardIds({
    required List<MyListEntry> entries,
    required List<int> pinned,
    int cap = cardCap,
  }) {
    final slots = <int>[];
    for (final id in pinned) {
      if (id > 0 && !slots.contains(id)) slots.add(id);
      if (slots.length >= cap) return slots;
    }

    final ranked = entries.where((e) => e.anilistId > 0 && !slots.contains(e.anilistId)).toList()
      ..sort((a, b) {
        final as = a.score, bs = b.score;
        if (as != null || bs != null) {
          if (as == null) return 1; // unrated after rated
          if (bs == null) return -1;
          final byScore = bs.compareTo(as);
          if (byScore != 0) return byScore;
        }
        final aAdded = a.addedAt, bAdded = b.addedAt;
        if (aAdded != null || bAdded != null) {
          if (aAdded == null) return 1; // pending write = newest = loses tie
          if (bAdded == null) return -1;
          final byAdded = aAdded.compareTo(bAdded);
          if (byAdded != 0) return byAdded;
        }
        return a.anilistId.compareTo(b.anilistId);
      });

    for (final e in ranked) {
      if (slots.length >= cap) break;
      slots.add(e.anilistId);
    }
    return slots;
  }

  /// Genre pills: frequency across every genre list, most frequent first,
  /// ties alphabetical. Computed at display time — never persisted.
  static List<String> rankGenres(Iterable<List<String>> genreLists, {int cap = genreCap}) {
    final counts = <String, int>{};
    for (final genres in genreLists) {
      for (final g in genres) {
        if (g.isEmpty) continue;
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final ranked = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return ranked.length > cap ? ranked.sublist(0, cap) : ranked;
  }

  // ── Read ────────────────────────────────────────────────────────────────

  /// Compute [uid]'s DNA. [pinned] and [firstAnimeId] come from the live
  /// user doc (identityProvider) so the caller re-fetches on override edits.
  ///
  /// Works for ANY uid: the myList read is owner-only under current rules,
  /// so another user's profile degrades to pinned cards + first anime (their
  /// derived portion and genres come out empty) instead of erroring.
  Future<AnimeDna> fetchDna({
    required String uid,
    required List<int> pinned,
    required int? firstAnimeId,
  }) async {
    List<MyListEntry> entries = const [];
    try {
      final snap = await _db.collection('users').doc(uid).collection('myList').get();
      entries = snap.docs.map(MyListEntry.fromDoc).toList();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('[AnimeDnaService] myList of $uid not readable — pinned/first only.');
    }

    final cardIds = deriveCardIds(entries: entries, pinned: pinned);
    final wanted = <int>{
      ...cardIds,
      ...entries.map((e) => e.anilistId).where((id) => id > 0),
      if (firstAnimeId != null && firstAnimeId > 0) firstAnimeId,
    };
    await _fetchMeta(wanted.toList());

    final scoreById = {
      for (final e in entries)
        if (e.score != null) e.anilistId: e.score!,
    };
    final cards = <AnimeDnaCard>[
      for (final id in cardIds)
        if (_metaCache[id] != null)
          AnimeDnaCard(
            anime: _metaCache[id]!,
            userScore: scoreById[id],
            pinned: pinned.contains(id),
          ),
    ];

    return AnimeDna(
      cards: cards,
      topGenres: rankGenres([
        for (final e in entries)
          if (_metaCache[e.anilistId] != null) _metaCache[e.anilistId]!.genres,
      ]),
      firstAnime: firstAnimeId == null ? null : _metaCache[firstAnimeId],
      listSize: entries.length,
    );
  }

  // ── Owner overrides (users/{uid} — anilistId ints only) ────────────────

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[AnimeDnaService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AnimeDnaService] $op failed: $e');
      rethrow;
    }
  }

  /// Replace the pinned set — deduped, positive ids only, capped at
  /// [UserData.maxDnaPinned]. An empty list means fully derived again.
  Future<void> setPinned(List<int> ids) {
    return _guard('setPinned', () async {
      final clean = <int>[];
      for (final id in ids) {
        if (id > 0 && !clean.contains(id)) clean.add(id);
        if (clean.length >= UserData.maxDnaPinned) break;
      }
      await _db.collection('users').doc(await _uid()).update({'dnaPinned': clean});
    });
  }

  /// Set the user-entered first anime (a personal fact — never derived).
  Future<void> setFirstAnime(int anilistId) {
    return _guard('setFirstAnime', () async {
      if (anilistId <= 0) throw ArgumentError('invalid anilistId: $anilistId');
      await _db.collection('users').doc(await _uid()).update({'firstAnimeId': anilistId});
    });
  }

  // ── AniList (single batched id_in fetch, session-cached) ───────────────

  static const String _metaQuery = r'''
query ($ids: [Int]) {
  Page(perPage: 50) {
    media(id_in: $ids, type: ANIME) {
      id
      title { english romaji }
      coverImage { large }
      seasonYear
      genres
      averageScore
    }
  }
}''';

  /// Resolves [ids] into [_metaCache] in `id_in` pages of 50 — one request
  /// per render for lists up to 50 anime. Failures only log; unresolved ids
  /// simply render no card.
  Future<void> _fetchMeta(List<int> ids) async {
    final missing = ids.where((id) => id > 0 && !_metaCache.containsKey(id)).toList();
    var requests = 0;
    for (var i = 0; i < missing.length; i += _metaPageSize) {
      final page = missing.sublist(i, min(i + _metaPageSize, missing.length));
      requests++;
      try {
        final res = await AniListRateLimiter.instance.send(
          () => http
              .post(
                Uri.parse(_endpoint),
                headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
                body: jsonEncode(<String, dynamic>{
                  'query': _metaQuery,
                  'variables': <String, dynamic>{'ids': page},
                }),
              )
              .timeout(_timeout),
          priority: true,
        );
        if (res.statusCode != 200) {
          debugPrint('[AnimeDnaService] AniList batch FAILED: status ${res.statusCode}\n${res.body}');
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
          final s = map['averageScore'];
          _metaCache[id] = DnaAnime(
            anilistId: id,
            title: ((title?['english'] ?? title?['romaji']) as String?)?.trim() ?? '',
            coverUrl: ((map['coverImage'] as Map<String, dynamic>?)?['large'] as String?) ?? '',
            seasonYear: (map['seasonYear'] as num?)?.toInt(),
            genres: (map['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
            communityScore: s is num ? s / 10.0 : 0.0,
          );
        }
      } catch (e) {
        debugPrint('[AnimeDnaService] AniList batch EXCEPTION: $e');
      }
    }
    if (missing.isNotEmpty) {
      debugPrint('[AnimeDnaService] resolved ${missing.length} ids in $requests AniList request(s).');
    }
  }
}
