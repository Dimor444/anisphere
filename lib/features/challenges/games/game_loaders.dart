import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../../services/anilist_rate_limiter.dart';
import 'emoji_anime_bank.dart';
import 'quiz_question.dart';

/// Thrown when a loader can't produce a usable question set — the QuizScreen
/// catches it (along with network errors) and shows its retry view.
class QuizLoadException implements Exception {
  final String message;
  const QuizLoadException(this.message);
  @override
  String toString() => message;
}

final Random _rand = Random();

const String _aniListEndpoint = 'https://graphql.anilist.co';
const Duration _timeout = Duration(seconds: 12);

/// POSTs a GraphQL [query] to AniList through the shared rate limiter
/// (high priority — gameplay must not be starved by cover-art fetches) and
/// returns the `data` map, throwing on any HTTP/GraphQL failure.
Future<Map<String, dynamic>> _aniListQuery(String query, Map<String, dynamic> variables) async {
  final res = await AniListRateLimiter.instance.send(
    () => http
        .post(
          Uri.parse(_aniListEndpoint),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({'query': query, 'variables': variables}),
        )
        .timeout(_timeout),
    priority: true,
  );
  if (res.statusCode != 200) {
    throw QuizLoadException('AniList responded with HTTP ${res.statusCode}');
  }
  final data = (jsonDecode(res.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>?;
  if (data == null) throw const QuizLoadException('AniList returned no data');
  return data;
}

/// [answer] + 3 distinct distractors drawn from [pool], shuffled. Returns the
/// options and the answer's index within them.
(List<String>, int) _buildOptions(String answer, List<String> pool) {
  final others = pool.where((p) => p != answer).toSet().toList()..shuffle(_rand);
  final options = <String>[answer, ...others.take(3)]..shuffle(_rand);
  return (options, options.indexOf(answer));
}

// ── Character Quiz ──────────────────────────────────────────────────────────

const String _characterQuery = r'''
query ($page: Int) {
  Page(page: $page, perPage: 25) {
    characters(sort: FAVOURITES_DESC) {
      id
      name { full }
      image { large }
    }
  }
}''';

/// Character Quiz: up to 8 "Who is this character?" questions from a random
/// page of AniList's most-favourited characters. Distractors are other names
/// from the same fetched pool. The complete list — every imageUrl included —
/// is built here before returning; nothing mutates it once the UI is up.
Future<List<QuizQuestion>> loadCharacterQuizQuestions() async {
  final data = await _aniListQuery(_characterQuery, {'page': 1 + _rand.nextInt(6)});
  final nodes = ((data['Page'] as Map<String, dynamic>?)?['characters'] as List<dynamic>?) ?? const [];

  final seen = <String>{};
  final pool = <({String name, String image})>[];
  for (final node in nodes) {
    final map = node as Map<String, dynamic>;
    final name = ((map['name'] as Map<String, dynamic>?)?['full'] as String?)?.trim();
    final image = (map['image'] as Map<String, dynamic>?)?['large'] as String?;
    if (name == null || name.isEmpty || image == null || image.isEmpty) continue;
    if (!seen.add(name.toLowerCase())) continue;
    pool.add((name: name, image: image));
  }
  // A question needs a correct answer + 3 distinct distractors.
  if (pool.length < 4) {
    throw const QuizLoadException('AniList returned too few characters');
  }

  pool.shuffle(_rand);
  final names = pool.map((c) => c.name).toList();
  final questions = <QuizQuestion>[];
  for (final c in pool.take(8)) {
    final (options, correctIndex) = _buildOptions(c.name, names);
    questions.add(QuizQuestion(
      question: 'Who is this character?',
      imageUrl: c.image,
      options: options,
      correctIndex: correctIndex,
    ));
  }
  return questions;
}

// ── Emoji Anime ─────────────────────────────────────────────────────────────

/// Emoji Anime: 10 random riddles from the offline bank. The emoji string is
/// stored as the question and rendered as the big prompt (no image). Async
/// only so all games share the QuizScreen loader signature.
Future<List<QuizQuestion>> loadEmojiAnimeQuestions() async {
  final bank = [...emojiAnimeBank]..shuffle(_rand);
  final titles = emojiAnimeBank.map((e) => e.title).toList();
  final questions = <QuizQuestion>[];
  for (final entry in bank.take(10)) {
    final (options, correctIndex) = _buildOptions(entry.title, titles);
    questions.add(QuizQuestion(
      question: entry.emojis,
      options: options,
      correctIndex: correctIndex,
    ));
  }
  return questions;
}

// ── Voice Match ─────────────────────────────────────────────────────────────

const String _voiceMatchQuery = r'''
query ($page: Int) {
  Page(page: $page, perPage: 20) {
    media(sort: POPULARITY_DESC, type: ANIME) {
      title { romaji }
      characters(role: MAIN, perPage: 2) {
        edges {
          node { name { full } image { large } }
          voiceActors(language: JAPANESE) { name { full } }
        }
      }
    }
  }
}''';

/// Voice Match: up to 8 "Who voices X?" questions matching main characters of
/// popular anime to their Japanese voice actors. Characters without a Japanese
/// VA are skipped, and each VA appears as the correct answer at most once per
/// session. Distractors are VA names of other fetched characters.
Future<List<QuizQuestion>> loadVoiceMatchQuestions() async {
  final data = await _aniListQuery(_voiceMatchQuery, {'page': 1 + _rand.nextInt(4)});
  final mediaList = ((data['Page'] as Map<String, dynamic>?)?['media'] as List<dynamic>?) ?? const [];

  final seenVas = <String>{};
  final seenChars = <String>{};
  final entries = <({String character, String anime, String? image, String va})>[];
  for (final rawMedia in mediaList) {
    final media = rawMedia as Map<String, dynamic>;
    final anime = ((media['title'] as Map<String, dynamic>?)?['romaji'] as String?)?.trim();
    if (anime == null || anime.isEmpty) continue;
    final edges = ((media['characters'] as Map<String, dynamic>?)?['edges'] as List<dynamic>?) ?? const [];
    for (final rawEdge in edges) {
      final edge = rawEdge as Map<String, dynamic>;
      final node = edge['node'] as Map<String, dynamic>?;
      final character = ((node?['name'] as Map<String, dynamic>?)?['full'] as String?)?.trim();
      final image = (node?['image'] as Map<String, dynamic>?)?['large'] as String?;
      final vas = (edge['voiceActors'] as List<dynamic>?) ?? const [];
      final va = vas.isEmpty
          ? null
          : (((vas.first as Map<String, dynamic>)['name'] as Map<String, dynamic>?)?['full'] as String?)?.trim();
      if (character == null || character.isEmpty) continue;
      if (va == null || va.isEmpty) continue; // no Japanese VA — skip
      if (!seenChars.add(character.toLowerCase())) continue;
      if (!seenVas.add(va.toLowerCase())) continue; // no duplicate correct answers
      entries.add((character: character, anime: anime, image: image, va: va));
    }
  }
  if (entries.length < 4) {
    throw const QuizLoadException('AniList returned too few voice actors');
  }

  entries.shuffle(_rand);
  final vaPool = entries.map((e) => e.va).toList();
  final questions = <QuizQuestion>[];
  for (final e in entries.take(8)) {
    final (options, correctIndex) = _buildOptions(e.va, vaPool);
    questions.add(QuizQuestion(
      question: 'Who voices ${e.character} (${e.anime})?',
      imageUrl: e.image,
      options: options,
      correctIndex: correctIndex,
    ));
  }
  return questions;
}
