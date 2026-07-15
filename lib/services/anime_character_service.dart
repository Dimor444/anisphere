import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'anilist_rate_limiter.dart';

/// The character's billing in this specific anime (AniList `CharacterRole`).
enum CharacterRole {
  main,
  supporting,
  background;

  static CharacterRole? fromApi(String? raw) => switch (raw) {
        'MAIN' => CharacterRole.main,
        'SUPPORTING' => CharacterRole.supporting,
        'BACKGROUND' => CharacterRole.background,
        _ => null,
      };
}

/// A single anime character — just what the True Fan quiz needs. [role] and
/// [favourites] drive question difficulty (obscure subjects, similar-fame
/// distractors); role is null when AniList doesn't report one.
class AnimeCharacter {
  final String name;
  final String? imageUrl;
  final CharacterRole? role;
  final int favourites;
  const AnimeCharacter({
    required this.name,
    this.imageUrl,
    this.role,
    this.favourites = 0,
  });
}

/// A resolved anime cast: the AniList media [id] (the stable key trueFanScores
/// docs are grouped by) plus its [characters]. [id] is null only when the
/// lookup failed and [characters] is empty.
class AnimeCast {
  final int? id;
  final List<AnimeCharacter> characters;
  const AnimeCast({this.id, this.characters = const []});
}

/// Fetches the cast of a given anime from the AniList GraphQL API
/// (https://graphql.anilist.co), which is far more reliable than Jikan/MAL.
///
/// A single query resolves the anime and up to 50 of its characters. AniList
/// caps the `Media.characters` connection at 25 per page (asking for more
/// silently clamps back to 25 — verified against the live API), so two pages
/// are aliased into the one request to get enough SUPPORTING/BACKGROUND
/// characters for large casts. `role` lives on the edge and `favourites` on
/// the node; both feed the True Fan difficulty logic.
///
/// AniList's search ranks the correct anime first, so we trust the top result
/// (no title-match gate). Results are cached per anime name, and any failure
/// resolves to an empty cast so callers can fall back gracefully.
class AnimeCharacterService {
  AnimeCharacterService._();

  /// Shared singleton so the cache is reused across the app.
  static final AnimeCharacterService instance = AnimeCharacterService._();

  static const String _aniListEndpoint = 'https://graphql.anilist.co';
  static const Duration _timeout = Duration(seconds: 10);

  static const String _query = r'''
query ($search: String) {
  Media(search: $search, type: ANIME) {
    id
    title { romaji english }
    page1: characters(sort: FAVOURITES_DESC, page: 1, perPage: 25) {
      edges {
        role
        node {
          name { full }
          image { large }
          favourites
        }
      }
    }
    page2: characters(sort: FAVOURITES_DESC, page: 2, perPage: 25) {
      edges {
        role
        node {
          name { full }
          image { large }
          favourites
        }
      }
    }
  }
}''';

  /// anime name (lower-cased) -> resolved cast. Only *successful* lookups
  /// (and definitive misses) are stored; transient failures are left out so
  /// they can be retried later.
  final Map<String, AnimeCast> _cache = <String, AnimeCast>{};

  /// Returns the AniList media id + characters for [animeName], or an empty
  /// cast on any failure.
  Future<AnimeCast> fetchCast(String animeName) async {
    final key = animeName.trim().toLowerCase();
    if (key.isEmpty) return const AnimeCast();

    final cached = _cache[key];
    if (cached != null) return cached;

    final requestBody = jsonEncode(<String, dynamic>{
      'query': _query,
      'variables': <String, dynamic>{'search': animeName},
    });

    // ── Diagnostic: exactly what we send ──────────────────────
    debugPrint('[AnimeCharacterService] POST $_aniListEndpoint for "$animeName"\n'
        '  query: $_query\n'
        '  variables: {"search":"$animeName"}');

    try {
      // High priority so the gameplay-critical cast fetch isn't starved by the
      // cover grid burst (AniList caps at ~30 requests/minute).
      final res = await AniListRateLimiter.instance.send(
        () => http
            .post(
              Uri.parse(_aniListEndpoint),
              headers: const {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: requestBody,
            )
            .timeout(_timeout),
        priority: true,
      );

      // ── Diagnostic: exactly what AniList returned ───────────
      debugPrint('[AnimeCharacterService] AniList raw response for "$animeName" '
          '(HTTP ${res.statusCode}):\n${res.body}');

      if (res.statusCode != 200) {
        debugPrint('[AnimeCharacterService] AniList request FAILED for "$animeName" — '
            'status ${res.statusCode} ${res.reasonPhrase}. '
            '${res.statusCode == 429 ? "RATE LIMITED (30 req/min)." : ""}');
        return const AnimeCast(); // transient — don't cache
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['errors'] != null) {
        debugPrint('[AnimeCharacterService] AniList GraphQL errors for "$animeName": ${body['errors']}');
      }

      final media = (body['data'] as Map<String, dynamic>?)?['Media'] as Map<String, dynamic>?;
      if (media == null) {
        debugPrint('[AnimeCharacterService] AniList: no Media for "$animeName" (data.Media is null).');
        return _cache[key] = const AnimeCast();
      }
      final mediaId = (media['id'] as num?)?.toInt();

      // Trust AniList's top result — no title-match gate (it only produced false
      // "mismatch" rejections that left the quiz with no character images).
      // page1 then page2 preserves the FAVOURITES_DESC ordering across both.
      final edges = <dynamic>[
        ...((media['page1'] as Map<String, dynamic>?)?['edges'] as List<dynamic>?) ?? const [],
        ...((media['page2'] as Map<String, dynamic>?)?['edges'] as List<dynamic>?) ?? const [],
      ];
      final characters = <AnimeCharacter>[];
      for (final edge in edges) {
        final map = edge as Map<String, dynamic>;
        final node = map['node'] as Map<String, dynamic>?;
        final name = (node?['name'] as Map<String, dynamic>?)?['full'] as String?;
        if (name == null || name.trim().isEmpty) continue;
        final image = (node?['image'] as Map<String, dynamic>?)?['large'] as String?;
        characters.add(AnimeCharacter(
          name: name.trim(),
          imageUrl: (image != null && image.isNotEmpty) ? image : null,
          role: CharacterRole.fromApi(map['role'] as String?),
          favourites: (node?['favourites'] as num?)?.toInt() ?? 0,
        ));
      }

      debugPrint('[AnimeCharacterService] "$animeName" (AniList id $mediaId): ${edges.length} edges returned → '
          '${characters.length} usable after filtering '
          '(${characters.where((c) => c.imageUrl != null).length} with images, '
          '${characters.where((c) => c.role == CharacterRole.supporting).length} supporting, '
          '${characters.where((c) => c.role == CharacterRole.background).length} background).');
      return _cache[key] = AnimeCast(id: mediaId, characters: characters);
    } on SocketException catch (e) {
      debugPrint('[AnimeCharacterService] socket error for "$animeName": $e');
      return const AnimeCast(); // transient — don't cache
    } on TimeoutException catch (e) {
      debugPrint('[AnimeCharacterService] timeout for "$animeName": $e');
      return const AnimeCast(); // transient — don't cache
    } catch (e, st) {
      debugPrint('[AnimeCharacterService] EXCEPTION for "$animeName": $e\n$st');
      return const AnimeCast();
    }
  }
}
