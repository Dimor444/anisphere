import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';
import 'auth_service.dart';

/// Watch status of a My List entry. Stored in Firestore as the uppercase
/// [value] (CURRENT / PLANNING / COMPLETED / DROPPED / PAUSED).
enum ListStatus {
  current('CURRENT', 'watching'),
  planning('PLANNING', 'planning'),
  completed('COMPLETED', 'completed'),
  dropped('DROPPED', 'dropped'),
  paused('PAUSED', 'onHold');

  final String value; // Firestore value
  final String trKey; // app_strings key for the label
  const ListStatus(this.value, this.trKey);

  static ListStatus fromValue(String? v) =>
      ListStatus.values.firstWhere((s) => s.value == v, orElse: () => ListStatus.planning);
}

/// One anime in the user's list (`users/{uid}/myList/{anilist_id}`).
///
/// Only list-keeping data lives here — full metadata (episode counts, air
/// dates, genres) is fetched from AniList by [MyListService.fetchMeta].
class MyListEntry {
  final int anilistId;
  final String title;
  final String coverImage;
  final ListStatus status;
  final double? score; // user rating 0–10, null if unrated
  final int episodesWatched;
  final String notes;
  final DateTime? addedAt;
  final DateTime? updatedAt;

  const MyListEntry({
    required this.anilistId,
    required this.title,
    required this.coverImage,
    required this.status,
    this.score,
    this.episodesWatched = 0,
    this.notes = '',
    this.addedAt,
    this.updatedAt,
  });

  factory MyListEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return MyListEntry(
      anilistId: (d['anilist_id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0,
      title: d['title'] as String? ?? '',
      coverImage: d['coverImage'] as String? ?? '',
      status: ListStatus.fromValue(d['status'] as String?),
      score: (d['score'] as num?)?.toDouble(),
      episodesWatched: (d['episodesWatched'] as num?)?.toInt() ?? 0,
      notes: d['notes'] as String? ?? '',
      addedAt: (d['addedAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// AniList metadata for the detail view — fetched on demand, never persisted.
class AniListMeta {
  final int episodes; // 0 if unknown / still airing
  final int? seasonYear;
  final List<String> genres;
  final String status; // RELEASING / FINISHED / …
  final double score; // community score out of 10

  const AniListMeta({
    required this.episodes,
    required this.seasonYear,
    required this.genres,
    required this.status,
    required this.score,
  });
}

/// The user's personal anime list, stored at `users/{uid}/myList` and keyed by
/// anilist_id for O(1) lookup.
///
/// Identity comes from [AuthService.initAuth], which falls back to a guest
/// (anonymous) session when no one is signed in.
///
/// All writes go through [_guard] so failures are logged and rethrown for the
/// UI to surface (error dialog + retry). Never touches aniGold/aniGem fields —
/// those are blocked by security rules on the client.
class MyListService {
  MyListService._();
  static final MyListService instance = MyListService._();

  static const int maxNoteLength = 500;

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<CollectionReference<Map<String, dynamic>>> _col() async {
    final uid = await _uid();
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('myList');
  }

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[MyListService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[MyListService] $op failed: $e');
      rethrow;
    }
  }

  // ── Writes ─────────────────────────────────────────────────────────────

  Future<void> addToMyList(int anilistId, String title, String coverImage, ListStatus status) {
    return _guard('add($anilistId)', () async {
      final col = await _col();
      await col.doc('$anilistId').set({
        'anilist_id': anilistId,
        'title': title,
        'coverImage': coverImage,
        'status': status.value,
        'score': null,
        'episodesWatched': 0,
        'notes': '',
        'addedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> removeFromMyList(int anilistId) {
    return _guard('remove($anilistId)', () async {
      final col = await _col();
      await col.doc('$anilistId').delete();
    });
  }

  Future<void> updateAnimeStatus(int anilistId, ListStatus newStatus) =>
      _update(anilistId, {'status': newStatus.value});

  Future<void> updateEpisodesWatched(int anilistId, int episodes) =>
      _update(anilistId, {'episodesWatched': episodes.clamp(0, 10000)});

  Future<void> updateScore(int anilistId, double? score) =>
      _update(anilistId, {'score': score?.clamp(0.0, 10.0)});

  Future<void> updateNotes(int anilistId, String notes) => _update(anilistId, {
        'notes': notes.length > maxNoteLength ? notes.substring(0, maxNoteLength) : notes,
      });

  /// Batched save from the detail editor — one write, one updatedAt bump.
  Future<void> updateEntry(
    int anilistId, {
    ListStatus? status,
    int? episodesWatched,
    double? score,
    bool clearScore = false,
    String? notes,
  }) {
    final fields = <String, dynamic>{
      if (status != null) 'status': status.value,
      if (episodesWatched != null) 'episodesWatched': episodesWatched.clamp(0, 10000),
      if (clearScore) 'score': null else if (score != null) 'score': score.clamp(0.0, 10.0),
      if (notes != null)
        'notes': notes.length > maxNoteLength ? notes.substring(0, maxNoteLength) : notes,
    };
    return _update(anilistId, fields);
  }

  Future<void> _update(int anilistId, Map<String, dynamic> fields) {
    return _guard('update($anilistId)', () async {
      final col = await _col();
      await col.doc('$anilistId').update({...fields, 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  /// Real-time stream of the full list, newest first.
  Stream<List<MyListEntry>> getMyList() async* {
    final col = await _col();
    yield* col.snapshots().map((snap) {
      final list = snap.docs.map(MyListEntry.fromDoc).toList();
      // Sort client-side: pending server timestamps arrive as null — pin those
      // (the just-added entries) to the top instead of flashing to the bottom.
      list.sort((a, b) {
        if (a.addedAt == null) return -1;
        if (b.addedAt == null) return 1;
        return b.addedAt!.compareTo(a.addedAt!);
      });
      return list;
    });
  }

  /// Real-time stream of a single entry — null when not in the list.
  Stream<MyListEntry?> watchEntry(int anilistId) async* {
    final col = await _col();
    yield* col.doc('$anilistId').snapshots().map((doc) => doc.exists ? MyListEntry.fromDoc(doc) : null);
  }

  Future<bool> isAnimeInMyList(int anilistId) {
    return _guard('lookup($anilistId)', () async {
      final col = await _col();
      final doc = await col.doc('$anilistId').get();
      return doc.exists;
    });
  }

  // ── AniList metadata (detail view) ─────────────────────────────────────

  static const String _metaQuery = r'''
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    episodes
    seasonYear
    genres
    status
    averageScore
  }
}''';

  final Map<int, AniListMeta> _metaCache = {};

  /// Episode count / year / genres for [anilistId]. Cached per session.
  /// Returns null on failure — the detail view degrades gracefully.
  Future<AniListMeta?> fetchMeta(int anilistId) async {
    final hit = _metaCache[anilistId];
    if (hit != null) return hit;

    try {
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse('https://graphql.anilist.co'),
              headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
              body: jsonEncode({
                'query': _metaQuery,
                'variables': {'id': anilistId},
              }),
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final media = (body['data'] as Map<String, dynamic>?)?['Media'] as Map<String, dynamic>?;
      if (media == null) return null;

      final s = media['averageScore'];
      final meta = AniListMeta(
        episodes: (media['episodes'] as num?)?.toInt() ?? 0,
        seasonYear: (media['seasonYear'] as num?)?.toInt(),
        genres: (media['genres'] as List<dynamic>?)?.cast<String>() ?? const [],
        status: media['status'] as String? ?? '',
        score: s is num ? s / 10.0 : 0.0,
      );
      _metaCache[anilistId] = meta;
      return meta;
    } catch (e) {
      debugPrint('[MyListService] fetchMeta($anilistId) failed: $e');
      return null;
    }
  }
}
