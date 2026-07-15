import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/anime_model.dart';
import '../../data/sample_data.dart' hide QuizQuestion;
import '../../services/challenge_attempts_service.dart';
import '../../services/anime_character_service.dart';
import '../../services/anime_image_service.dart';
import '../../services/anime_search_service.dart';
import '../../services/true_fan_score_service.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/anime_cover_image.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../widgets/anime_challenge_card.dart';
import '../../widgets/true_fan_result_card.dart';
import 'true_fan_leaderboard.dart';
import 'games/game_loaders.dart';
import 'games/quiz_question.dart';
import 'games/quiz_screen.dart';

class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});
  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen> {
  int _remaining = ChallengeAttemptsService.maxDailyAttempts;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh(); // re-check when the screen is (re)shown — handles the midnight reset
  }

  Future<void> _refresh() async {
    final r = await ChallengeAttemptsService().getRemainingAttempts();
    if (mounted) setState(() => _remaining = r);
  }

  /// Shared gate for EVERY challenge entry point (Games cards + True Fan).
  /// AniPlus members are unlimited; everyone else spends one attempt from the
  /// single shared daily pool. Shows the "no attempts" dialog and returns false
  /// when the pool is empty — callers must not start the game in that case.
  Future<bool> _gate() async {
    if (ref.read(isPlusProvider)) return true;
    final ok = await ChallengeAttemptsService().consumeAttempt();
    if (!mounted) return ok;
    if (!ok) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('No attempts left today'),
          content: const Text('Come back tomorrow! (Resets at midnight)'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    await _refresh();
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final isPlus = ref.watch(isPlusProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Challenges'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Games'), Tab(text: '🎯 True Fan'), Tab(text: '⚔️ League'), Tab(text: '🎯 Events')],
          ),
        ),
        body: Column(
          children: [
            // Shared daily-attempts indicator (below the tab bar).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.surface,
              child: Text(
                isPlus
                    ? '🎮 Daily Attempts: ∞ (AniPlus)'
                    : '🎮 Daily Attempts: $_remaining / ${ChallengeAttemptsService.maxDailyAttempts} remaining',
                style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                _GamesTab(gate: _gate),
                _TrueFanTab(gate: _gate, remaining: _remaining),
                const _LeagueTab(),
                const _EventsTab(),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Games
class _GamesTab extends StatelessWidget {
  final Future<bool> Function() gate;
  const _GamesTab({required this.gate});
  @override
  Widget build(BuildContext context) {
    // Each game shows a real anime cover behind it (with the game's emoji + title overlaid).
    // A null loader marks a game that isn't playable yet (Coming soon).
    const games = <_GameDef>[
      _GameDef('🎵', 'Guess the Opening', 50, AppGradients.brand, 'Attack on Titan', null),
      _GameDef('👤', 'Character Quiz', 40, AppGradients.purpleCyan, 'Naruto', loadCharacterQuizQuestions),
      _GameDef('😄', 'Emoji Anime', 30, AppGradients.gem, 'One Piece', loadEmojiAnimeQuestions),
      _GameDef('🗣️', 'Voice Match', 60, AppGradients.gold, 'Demon Slayer', loadVoiceMatchQuestions),
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95),
      itemCount: games.length,
      itemBuilder: (context, i) {
        final g = games[i];
        return GestureDetector(
          onTap: () async {
            Haptics.light();
            final loader = g.loader;
            if (loader == null) {
              // Needs audio playback — arriving in a later update.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🎵 Guess the Opening is coming soon!')),
              );
              return;
            }
            // Spend a shared daily attempt BEFORE opening the game.
            if (await gate() && context.mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuizScreen(
                    title: '${g.emoji}  ${g.title}',
                    totalReward: g.reward,
                    loadQuestions: loader,
                    gate: gate,
                  ),
                ),
              );
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimeCoverImage(animeName: g.cover, gradient: g.gradient, emoji: g.emoji, emojiSize: 40),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black26, Colors.black87],
                      stops: [0.25, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(12)),
                        child: Text(g.emoji, style: const TextStyle(fontSize: 24)),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(g.title, style: AppTextStyles.subheading.copyWith(color: Colors.white)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(20)),
                            child: Text('▶ Play  ·  +${g.reward}🟡', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A game card in the Games grid. [loader] builds a fresh, fully-populated
/// question set each run (see QuizScreen); a null loader marks a game that
/// isn't playable yet — tapping it shows a "Coming soon" snackbar instead.
class _GameDef {
  final String emoji, title, cover;
  final int reward;
  final Gradient gradient;
  final Future<List<QuizQuestion>> Function()? loader;
  const _GameDef(this.emoji, this.title, this.reward, this.gradient, this.cover, this.loader);
}

// ───────────────────────── TRUE FAN
class _TrueFanTab extends ConsumerStatefulWidget {
  final Future<bool> Function() gate;
  final int remaining;
  const _TrueFanTab({required this.gate, required this.remaining});
  @override
  ConsumerState<_TrueFanTab> createState() => _TrueFanTabState();
}

class _TrueFanTabState extends ConsumerState<_TrueFanTab> {
  static const double _avatarSize = 182; // ~1.4× the previous 130px circle

  int _phase = 0; // 0 select, 1 quiz, 2 results
  _SelectedAnime? _selectedAnime;

  // search state
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<_SelectedAnime>? _searchResults;
  bool _searchLoading = false;
  Timer? _debounce;

  // result-card state
  final GlobalKey _cardKey = GlobalKey(); // captured for the shareable image
  String? _coverUrl; // anime cover for the result card
  bool _sharing = false;

  // quiz state
  late List<_FanQuestion> _questions;
  int? _anilistId; // AniList media id of the selected anime — keys trueFanScores
  bool _loadingChars = false; // fetching the anime's cast before the quiz starts
  bool _loadError = false; // AniList couldn't return a usable cast
  int? _countdown; // 3 → 2 → 1 → 0 (Start!) before the first question; null = running
  Timer? _countdownTimer;
  int _qIndex = 0;
  int _correct = 0;
  int? _selected;
  bool _locked = false;
  Timer? _timer;
  int _elapsedMs = 0;
  bool _showFloat = false;

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Entry point for True Fan — spends a shared daily attempt first.
  Future<void> _onStart() async {
    if (await widget.gate()) _start();
  }

  Future<void> _start() async {
    final sel = _selectedAnime;
    if (sel == null) return;
    _timer?.cancel();
    _countdownTimer?.cancel();
    setState(() {
      _phase = 1;
      _loadingChars = true;
      _loadError = false;
      _countdown = null;
      _qIndex = 0;
      _correct = 0;
      _selected = null;
      _locked = false;
      _showFloat = false;
      _elapsedMs = 0;
      _coverUrl = null;
      _anilistId = null;
    });

    // Warm the cover image for the eventual result card (cached for the card).
    _loadResultCover(sel.title);

    // Pull the real cast from AniList.
    final cast = await AnimeCharacterService.instance.fetchCast(sel.title);
    if (!mounted) return;
    _anilistId = cast.id;

    final questions = _buildQuestions(sel, cast.characters);
    if (questions == null) {
      // No usable cast (AniList failed / rate-limited) — don't fake it.
      setState(() {
        _loadingChars = false;
        _loadError = true;
      });
      return;
    }

    setState(() {
      _questions = questions;
      _loadingChars = false;
    });

    // Show a 3-2-1 countdown before the first question (and the clock).
    _beginCountdown();
  }

  void _beginCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 3);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown! > 0) {
        Haptics.light();
        setState(() => _countdown = _countdown! - 1);
      } else {
        // "Start!" has shown for a beat — begin the quiz.
        t.cancel();
        Haptics.medium();
        setState(() => _countdown = null);
        _startQuizTimer();
      }
    });
  }

  void _startQuizTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 47), (_) {
      setState(() => _elapsedMs += 47);
    });
  }

  Future<void> _loadResultCover(String title) async {
    // High priority: the selected anime's cover for the result card.
    final result = await AnimeImageService.instance.fetchImage(title, priority: true);
    if (!mounted) return;
    setState(() => _coverUrl = result.url);
  }

  // TODO: replace with real backend leaderboard
  int _calculateRank(int score, double timeTaken) {
    return max(1, 50000 - (score * 4000) + (timeTaken * 10).round());
  }

  /// Captures the result card ([_cardKey]'s RepaintBoundary) to a PNG and opens
  /// the system share sheet with it.
  Future<void> _shareCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Make sure the latest frame (cover image, etc.) is painted before capture.
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;

      final dir = await Directory.systemTemp.createTemp('anisphere_truefan');
      final file = File('${dir.path}/true_fan_result.png');
      await file.writeAsBytes(data.buffer.asUint8List());

      final anime = _selectedAnime?.title ?? 'this anime';
      // sharePositionOrigin is required for iPad to anchor the share popover.
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: "I just proved I'm a True Fan of $anime! 🎌 #AniSphere",
        sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t share the card: $e'), duration: const Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Search ──────────────────────────────────────────────────
  void _onSearchChanged(String text) {
    setState(() => _query = text);
    _debounce?.cancel();
    if (text.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _searchLoading = false;
      });
      return;
    }
    setState(() => _searchLoading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = text.trim();
      final raw = await AnimeSearchService.instance.searchAnime(q);
      if (!mounted || q != _query.trim()) return; // a newer keystroke superseded this
      setState(() {
        _searchResults = raw
            .map((r) => _SelectedAnime(title: r.title, genre: r.genre, rating: r.rating))
            .toList();
        _searchLoading = false;
      });
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _searchResults = null;
      _searchLoading = false;
    });
  }

  /// Builds 10 questions from the fetched [characters], which arrive in AniList
  /// FAVOURITES_DESC order (index 0 = most famous). Question subjects are drawn
  /// from SUPPORTING characters (topped up with BACKGROUND when there aren't
  /// ~10 of them) — never MAIN — so only real fans recognize the faces. Titles
  /// whose supporting cast is too small (movies, short OVAs) fall back to the
  /// whole cast minus its most famous name(s), MAIN included, so every title
  /// still fills a 10-question session. Wrong options are same-anime characters
  /// with the closest favourites counts to the answer's, so nothing can be
  /// eliminated on fame alone. Returns `null` when there aren't enough
  /// characters (caller shows a "couldn't load" view — we never fabricate
  /// questions from a different anime).
  List<_FanQuestion>? _buildQuestions(_SelectedAnime sel, List<AnimeCharacter> characters) {
    // De-duplicate by name, preserving the favourites ranking (index = rank).
    final seen = <String>{};
    final distinct = <AnimeCharacter>[];
    for (final c in characters) {
      final name = c.name.trim();
      if (name.isEmpty) continue;
      if (seen.add(name.toLowerCase())) distinct.add(c);
    }

    debugPrint('[TrueFan] "${sel.title}": fetched ${characters.length} characters, '
        '${distinct.length} distinct, ${distinct.where((c) => (c.imageUrl ?? '').isNotEmpty).length} with images.');

    // Need a correct answer + 2 distinct wrong options.
    if (distinct.length < 3) {
      debugPrint('[TrueFan] Too few characters for "${sel.title}" (${distinct.length}) — showing load-error view.');
      return null;
    }

    final rand = Random();
    const total = 10;

    // Correct answers need a recognizable image; only if not a single character
    // has one do we use everything (the avatar falls back to emoji).
    var eligible = <int>[
      for (var i = 0; i < distinct.length; i++)
        if ((distinct[i].imageUrl ?? '').isNotEmpty) i,
    ];
    if (eligible.isEmpty) eligible = List.generate(distinct.length, (i) => i);

    // Primary subject pool: SUPPORTING roles, topped up with BACKGROUND when
    // supporting alone can't fill a session. MAIN never enters this path.
    var subjects = eligible.where((i) => distinct[i].role == CharacterRole.supporting).toList();
    if (subjects.length < total) {
      subjects.addAll(eligible.where((i) => distinct[i].role == CharacterRole.background));
    }

    if (subjects.length < total) {
      // Small-cast fallback (movies, short OVAs): skip only the most famous
      // character — or the top 3 when the cast is big enough to spare them —
      // and draw subjects from the rest, MAIN included.
      final skip = eligible.length >= total + 3 ? 3 : 1;
      subjects = eligible.length > skip ? eligible.sublist(skip) : eligible;
      debugPrint('[TrueFan] "${sel.title}": supporting cast too small — '
          'fallback pool of ${subjects.length} (skipped top $skip).');
    }

    // No repeated subject across the session; only cycle when the pool is
    // smaller than 10 so tiny casts still fill every question.
    final bag = [...subjects]..shuffle(rand);
    final correctRanks = <int>[for (var i = 0; i < total; i++) bag[i % bag.length]];

    final questions = <_FanQuestion>[];
    for (final rank in correctRanks) {
      final correct = distinct[rank];
      final options = <String>[correct.name, ..._hardDistractors(distinct, rank, rand)]..shuffle(rand);
      questions.add(_FanQuestion(
        answer: correct.name,
        options: options,
        emoji: sel.emoji,
        imageUrl: correct.imageUrl,
      ));
      debugPrint('[TrueFan] Q answer="${correct.name}" rank=$rank role=${correct.role} '
          'favourites=${correct.favourites} imageUrl=${correct.imageUrl ?? "NULL"}');
    }
    return questions;
  }

  /// Two wrong-answer names picked from the same anime's characters whose
  /// favourites counts sit closest to the correct answer's — an option can't
  /// be ruled out just for being obviously more or less famous. Rank distance
  /// breaks ties so casts where AniList reports zero favourites still degrade
  /// to similar-prominence picks.
  List<String> _hardDistractors(List<AnimeCharacter> distinct, int correctIdx, Random rand) {
    final correct = distinct[correctIdx];
    final correctName = correct.name.toLowerCase();
    final ranked = <(int favGap, int rankGap, String name)>[];
    for (var i = 0; i < distinct.length; i++) {
      if (i == correctIdx) continue;
      if (distinct[i].name.toLowerCase() == correctName) continue;
      ranked.add((
        (distinct[i].favourites - correct.favourites).abs(),
        (i - correctIdx).abs(),
        distinct[i].name,
      ));
    }
    ranked.sort((a, b) {
      final byFav = a.$1.compareTo(b.$1);
      return byFav != 0 ? byFav : a.$2.compareTo(b.$2);
    });
    final pool = ranked.take(5).map((e) => e.$3).toList()..shuffle(rand);
    return pool.take(2).toList();
  }

  void _answer(int i) {
    if (_locked) return;
    Haptics.medium();
    final q = _questions[_qIndex];
    final correct = q.options[i] == q.answer;
    setState(() {
      _selected = i;
      _locked = true;
      if (correct) {
        _correct++;
        _showFloat = true;
      }
    });
    Future.delayed(Duration(milliseconds: correct ? 500 : 1000), () {
      if (!mounted) return;
      if (_qIndex < _questions.length - 1) {
        setState(() {
          _qIndex++;
          _selected = null;
          _locked = false;
          _showFloat = false;
        });
      } else {
        _timer?.cancel();
        _recordPass();
        setState(() => _phase = 2);
      }
    });
  }

  /// Fire-and-forget: upsert this run onto the trueFanScores leaderboard when
  /// it's a PASS (service enforces the threshold and keeps the best time).
  /// The results screen must render even if the write fails or the AniList id
  /// never resolved.
  void _recordPass() {
    final anilistId = _anilistId;
    final title = _selectedAnime?.title;
    if (anilistId == null || title == null) return;
    TrueFanScoreService.instance
        .submitPass(
          anilistId: anilistId,
          animeTitle: title,
          score: _correct,
          timeSeconds: _elapsedMs / 1000.0,
        )
        .catchError((Object e) {
      debugPrint('[TrueFan] score submit failed: $e');
      return false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      0 => _select(),
      1 => _quiz(),
      _ => _results(),
    };
  }

  // Step 1
  Widget _select() {
    final isPlus = ref.watch(isPlusProvider);
    final searching = _query.trim().isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              const Expanded(child: Text('Pick an anime to prove yourself', style: AppTextStyles.subheading)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                child: Text(isPlus ? '∞ today' : '${widget.remaining}/4 today', style: AppTextStyles.numbers.copyWith(color: isPlus ? AppColors.aniGold : AppColors.textPrimary)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: 'Search any anime…',
              prefixIcon: const Icon(LucideIcons.search, size: 18, color: AppColors.textMuted),
              suffixIcon: searching
                  ? IconButton(icon: const Icon(LucideIcons.x, size: 18, color: AppColors.textMuted), onPressed: _clearSearch)
                  : null,
              filled: true,
              fillColor: AppColors.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary)),
            ),
          ),
        ),
        Expanded(child: searching ? _searchGrid() : _animeGrid(SampleData.animeList.map(_SelectedAnime.fromModel).toList())),
        if (_selectedAnime != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: GradientButton(label: 'Start Challenge →', onPressed: _onStart),
            ),
          ),
      ],
    );
  }

  Widget _searchGrid() {
    if (_searchLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    final results = _searchResults ?? const <_SelectedAnime>[];
    if (results.isEmpty) {
      return const Center(child: Text('No anime found', style: AppTextStyles.bodyMuted));
    }
    return _animeGrid(results);
  }

  Widget _animeGrid(List<_SelectedAnime> items) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.72),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final a = items[i];
        return AnimeChallengeCard(
          animeName: a.title,
          genre: a.genre,
          rating: a.rating,
          selected: _selectedAnime?.title == a.title,
          onTap: () {
            Haptics.light();
            setState(() => _selectedAnime = a);
          },
        );
      },
    );
  }

  // Step 2
  Widget _quiz() {
    if (_loadingChars) {
      return const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('Loading characters…', style: AppTextStyles.bodyMuted),
            ],
          ),
        ),
      );
    }
    if (_loadError) return _loadErrorView();
    if (_countdown != null) return _countdownView();
    final q = _questions[_qIndex];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Text('Q${_qIndex + 1}/10', style: AppTextStyles.numbersLg()),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                  child: Row(children: [
                    const Icon(LucideIcons.timer, size: 14, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text(Fmt.stopwatch(_elapsedMs), style: AppTextStyles.numbers.copyWith(color: AppColors.accent)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: (_qIndex + 1) / 10, minHeight: 6, backgroundColor: AppColors.surface, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            ),
            const Spacer(),
            Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: _avatarSize, height: _avatarSize,
                  decoration: BoxDecoration(
                    gradient: AppGradients.forSeed(q.answer),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppGradients.pairForSeed(q.answer).last.withOpacity(0.5), blurRadius: 36)],
                  ),
                  alignment: Alignment.center,
                  child: _characterAvatar(q),
                ),
                if (_showFloat)
                  Positioned(
                    top: -30,
                    child: Text('+1 Correct!', style: AppTextStyles.subheading.copyWith(color: AppColors.success))
                        .animate().slideY(begin: 0, end: -1, duration: 600.ms).fadeOut(delay: 300.ms),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Who is this character?', style: AppTextStyles.heading),
            const SizedBox(height: 20),
            ...List.generate(q.options.length, (i) {
              final correct = q.options[i] == q.answer;
              Color? bg, border;
              if (_locked) {
                if (correct) {
                  bg = AppColors.success.withOpacity(0.2);
                  border = AppColors.success;
                } else if (_selected == i) {
                  bg = AppColors.error.withOpacity(0.2);
                  border = AppColors.error;
                }
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GestureDetector(
                  onTap: () => _answer(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                    decoration: BoxDecoration(
                      color: bg ?? AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border ?? AppColors.border, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: Text(q.options[i], style: AppTextStyles.subheading.copyWith(fontWeight: FontWeight.w600))),
                        if (_locked && correct) const Icon(LucideIcons.check, color: AppColors.success),
                        if (_locked && !correct && _selected == i) const Icon(LucideIcons.x, color: AppColors.error),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  /// Portrait shown in the top circle. Loads the real AniList character image
  /// (with a spinner while it loads); falls back to the question's emoji when
  /// there's no image URL or the download fails.
  Widget _characterAvatar(_FanQuestion q) {
    final emoji = Text(q.emoji, style: const TextStyle(fontSize: 90));
    final url = q.imageUrl;
    if (url == null || url.isEmpty) {
      debugPrint('[TrueFan] avatar for "${q.answer}": imageUrl is NULL → showing emoji ${q.emoji}');
      return emoji;
    }
    return ClipOval(
      child: Image.network(
        url,
        width: _avatarSize,
        height: _avatarSize,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child; // done loading
          return const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.8, color: Colors.white),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('[TrueFan] avatar image FAILED for "${q.answer}" url=$url error=$error');
          return Center(child: emoji);
        },
      ),
    );
  }

  /// Full-screen "Get Ready" 3-2-1 countdown shown before the first question.
  Widget _countdownView() {
    final label = _countdown! > 0 ? '$_countdown' : 'Start!';
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Get Ready', style: AppTextStyles.heading),
            const SizedBox(height: 28),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Container(
                key: ValueKey(label),
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  gradient: AppGradients.brand,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 36)],
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: _countdown! > 0 ? 64 : 40,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when AniList returns no usable cast — instead of faking questions
  /// from a different anime, we tell the user and let them retry or repick.
  Widget _loadErrorView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 46, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text("Couldn't load characters", style: AppTextStyles.heading, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'AniList didn’t return this anime’s cast — it may be momentarily rate-limited. Try again in a moment, or pick another anime.',
              style: AppTextStyles.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity, child: GradientButton(label: 'Try Again', onPressed: _start)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() {
                _phase = 0;
                _loadError = false;
              }),
              child: const Text('Pick another anime',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // Step 3
  Widget _results() {
    final user = ref.watch(userProvider);
    final timeSeconds = _elapsedMs / 1000.0;
    final rank = _calculateRank(_correct, timeSeconds);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SizedBox(height: 6),
          // The shareable trophy card — wrapped so we can capture just this.
          Center(
            child: RepaintBoundary(
              key: _cardKey,
              child: TrueFanResultCard(
                animeName: _selectedAnime?.title ?? 'Anime',
                coverUrl: _coverUrl,
                score: _correct,
                timeSeconds: timeSeconds,
                rank: rank,
                user: user,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: GradientButton(label: 'Play Again', onPressed: () => setState(() => _phase = 0))),
              const SizedBox(width: 12),
              Expanded(child: _shareButton()),
            ],
          ),
          const SizedBox(height: 18),
          const SectionHeader(title: 'Fastest True Fans', padding: EdgeInsets.only(bottom: 10)),
          TrueFanLeaderboard(anilistId: _anilistId),
        ],
      ),
    );
  }

  Widget _shareButton() {
    return GestureDetector(
      onTap: _sharing ? null : _shareCard,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: _sharing
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.share2, size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text('Share Card', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}

/// A True Fan quiz question. Mirrors the bundled sample-data question shape
/// (answer + options) but also carries the real character [imageUrl] when one
/// was fetched from AniList; [emoji] is the fallback when no image is available.
class _FanQuestion {
  final String answer;
  final List<String> options;
  final String emoji;
  final String? imageUrl;
  const _FanQuestion({
    required this.answer,
    required this.options,
    required this.emoji,
    this.imageUrl,
  });
}

/// The anime the player picked for a challenge — from the preset grid (via
/// [_SelectedAnime.fromModel]) or an AniList search result. [emoji] is the
/// per-question avatar fallback when a character image can't be loaded.
class _SelectedAnime {
  final String title;
  final String genre;
  final double rating;
  final String emoji;
  const _SelectedAnime({
    required this.title,
    required this.genre,
    required this.rating,
    this.emoji = '🎬',
  });

  factory _SelectedAnime.fromModel(AnimeModel a) =>
      _SelectedAnime(title: a.title, genre: a.genre, rating: a.score, emoji: a.emoji);
}

// ───────────────────────── LEAGUE
class _LeagueTab extends StatelessWidget {
  const _LeagueTab();
  @override
  Widget build(BuildContext context) {
    final tiers = ['Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Master'];
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Spring Season', style: AppTextStyles.heading.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text('Ends in 12d 4h', style: AppTextStyles.bodyMuted.copyWith(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
          child: Column(children: [
            const Text('🏆', style: TextStyle(fontSize: 50)),
            const Text('Gold III', style: AppTextStyles.heading),
            const SizedBox(height: 12),
            const Row(children: [
              Text('1,980 LP', style: AppTextStyles.numbers),
              Spacer(),
              Text('320 to Platinum', style: AppTextStyles.captionMuted),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: const LinearProgressIndicator(value: 0.72, minHeight: 10, backgroundColor: AppColors.background, valueColor: AlwaysStoppedAnimation(AppColors.aniGold)),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tiers.length,
            separatorBuilder: (_, __) => const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(LucideIcons.chevronRight, size: 14, color: AppColors.textMuted)),
            itemBuilder: (_, i) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: i == 2 ? AppColors.aniGold.withOpacity(0.2) : AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: i == 2 ? AppColors.aniGold : AppColors.border)),
              alignment: Alignment.center,
              child: Text(tiers[i], style: AppTextStyles.caption.copyWith(color: i == 2 ? AppColors.aniGold : AppColors.textSecondary, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
        const SectionHeader(title: 'Earn LP', padding: EdgeInsets.only(top: 16, bottom: 10)),
        const Wrap(spacing: 8, runSpacing: 8, children: [
          _LpChip('True Fan 10/10', '+100'), _LpChip('Daily login', '+20'),
          _LpChip('Win a game', '+50'), _LpChip('7-day streak', '+150'),
        ]),
        const SectionHeader(title: 'Top 10', padding: EdgeInsets.only(top: 16, bottom: 10)),
        ...SampleData.leagueLeaders.map((l) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: l.user.id == 'u_me' ? AppColors.primary : AppColors.border)),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${l.rank}', style: AppTextStyles.numbersLg())),
                const SizedBox(width: 8),
                UserAvatar.fromUser(l.user, radius: 16),
                const SizedBox(width: 10),
                Expanded(child: Text(l.user.username, style: AppTextStyles.label)),
                Text('${Fmt.thousands(l.lp)} LP', style: AppTextStyles.numbers.copyWith(color: AppColors.aniGold)),
              ]),
            )),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: AppGradients.gold, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            const Text('🏆', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Weekly Tournament', style: AppTextStyles.subheading.copyWith(color: Colors.white)),
              Text('Starts Saturday · 500🟡 prize', style: AppTextStyles.caption.copyWith(color: Colors.white70)),
            ])),
            const Icon(LucideIcons.chevronRight, color: Colors.white),
          ]),
        ),
      ],
    );
  }
}

class _LpChip extends StatelessWidget {
  final String label;
  final String lp;
  const _LpChip(this.label, this.lp);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
        const SizedBox(width: 6),
        Text(lp, style: AppTextStyles.numbers.copyWith(color: AppColors.success)),
      ]),
    );
  }
}

// ───────────────────────── EVENTS
class _EventsTab extends StatelessWidget {
  const _EventsTab();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Text('📅', style: TextStyle(fontSize: 24)), const SizedBox(width: 10), const Text('30-Day Challenge', style: AppTextStyles.subheading), const Spacer(), Text('Day 12/30', style: AppTextStyles.numbers.copyWith(color: AppColors.primaryLight))]),
            const SizedBox(height: 14),
            ...['Watch a 2024 anime', 'React to 5 posts', 'Play True Fan', 'Add 3 to your list'].asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(e.key < 2 ? LucideIcons.checkCircle2 : LucideIcons.circle, size: 18, color: e.key < 2 ? AppColors.success : AppColors.textMuted),
                    const SizedBox(width: 10),
                    Text(e.value, style: AppTextStyles.body.copyWith(color: e.key < 2 ? AppColors.textMuted : AppColors.textPrimary, decoration: e.key < 2 ? TextDecoration.lineThrough : null)),
                  ]),
                )),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: AppGradients.purpleCyan, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Text('🐉', style: TextStyle(fontSize: 24)), const SizedBox(width: 10), Text('Community Raid', style: AppTextStyles.subheading.copyWith(color: Colors.white)), const Spacer(), Text('2d 6h left', style: AppTextStyles.caption.copyWith(color: Colors.white70))]),
            const SizedBox(height: 12),
            Text('Watch 1M episodes together', style: AppTextStyles.body.copyWith(color: Colors.white)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(5), child: const LinearProgressIndicator(value: 0.68, minHeight: 10, backgroundColor: Colors.black26, valueColor: AlwaysStoppedAnimation(Colors.white))),
            const SizedBox(height: 6),
            Text('684,201 / 1,000,000', style: AppTextStyles.caption.copyWith(color: Colors.white70)),
          ]),
        ),
        const SectionHeader(title: 'Upcoming Events', padding: EdgeInsets.only(top: 16, bottom: 10)),
        ...[('🌸', 'Spring Watch Party', 'Apr 14'), ('🎮', 'Trivia Royale', 'Apr 20'), ('🎨', 'Fan Art Contest', 'May 1')].map((e) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                Text(e.$1, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(child: Text(e.$2, style: AppTextStyles.subheading)),
                Text(e.$3, style: AppTextStyles.captionMuted),
              ]),
            )),
      ],
    );
  }
}
