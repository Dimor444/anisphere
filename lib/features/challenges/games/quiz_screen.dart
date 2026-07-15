import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_gradients.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptics.dart';
import '../../../services/pending_gold_service.dart';
import '../../../shared/providers/currency_provider.dart';
import '../../../shared/widgets/gradient_button.dart';
import 'quiz_question.dart';
import 'results_screen.dart';

enum _QuizPhase { loading, error, playing, finished }

/// Shared quiz engine for the Challenges → Games mini-games.
///
/// Parameterized by the game [title], the [totalReward] (AniGold for a perfect
/// run) and a [loadQuestions] loader that must return a fully-built question
/// list — including every imageUrl — before the quiz UI renders. Questions are
/// never mutated after loading.
class QuizScreen extends ConsumerStatefulWidget {
  final String title;
  final int totalReward;
  final Future<List<QuizQuestion>> Function() loadQuestions;

  /// Shared daily-attempts gate, re-run when the player taps "Play Again".
  /// (The first attempt is consumed by the Games tab before navigating here.)
  final Future<bool> Function()? gate;

  const QuizScreen({
    super.key,
    required this.title,
    required this.totalReward,
    required this.loadQuestions,
    this.gate,
  });

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  static const int _secondsPerQuestion = 15;
  static const Duration _advanceDelay = Duration(milliseconds: 1200);

  _QuizPhase _phase = _QuizPhase.loading;
  List<QuizQuestion> _questions = const [];
  int _index = 0;
  int _score = 0;
  int? _picked; // null while unanswered (and on timeout)
  bool _locked = false;
  int _secondsLeft = _secondsPerQuestion;
  int _goldEarned = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    setState(() {
      _phase = _QuizPhase.loading;
      _index = 0;
      _score = 0;
      _picked = null;
      _locked = false;
      _goldEarned = 0;
    });
    try {
      final questions = await widget.loadQuestions();
      if (!mounted) return;
      if (questions.isEmpty) throw StateError('loader returned no questions');
      setState(() {
        _questions = questions;
        _phase = _QuizPhase.playing;
      });
      _startTimer();
    } catch (e) {
      debugPrint('[QuizScreen] "${widget.title}" failed to load questions: $e');
      if (mounted) setState(() => _phase = _QuizPhase.error);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _secondsPerQuestion);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        _timeout();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  /// Time ran out — counts as a wrong answer; the correct option is revealed.
  void _timeout() {
    if (_locked) return;
    Haptics.medium();
    setState(() {
      _secondsLeft = 0;
      _picked = null;
      _locked = true;
    });
    Future.delayed(_advanceDelay, () {
      if (mounted) _next();
    });
  }

  void _answer(int i) {
    if (_locked) return;
    _timer?.cancel();
    Haptics.medium();
    setState(() {
      _picked = i;
      _locked = true;
      if (i == _questions[_index].correctIndex) _score++;
    });
    Future.delayed(_advanceDelay, () {
      if (mounted) _next();
    });
  }

  void _next() {
    if (_index < _questions.length - 1) {
      setState(() {
        _index++;
        _picked = null;
        _locked = false;
      });
      _startTimer();
    } else {
      _finish();
    }
  }

  /// AniGold is proportional: (reward ÷ question count) × correct answers.
  /// It is NOT written to Firestore (users.aniGold is rule-protected; Cloud
  /// Functions will credit it later) — it accumulates in the local
  /// "pending_anigold" ledger, plus the in-session wallet display.
  Future<void> _finish() async {
    _timer?.cancel();
    final gold = (widget.totalReward * _score / _questions.length).round();
    if (gold > 0) {
      await PendingGoldService.instance.add(gold);
      if (!mounted) return;
      ref.read(currencyProvider.notifier).addGold(gold);
    }
    if (_score == _questions.length) Haptics.heavy();
    setState(() {
      _goldEarned = gold;
      _phase = _QuizPhase.finished;
    });
  }

  Future<void> _playAgain() async {
    // Replays spend a shared daily attempt too; the gate shows the
    // "no attempts" dialog itself when the pool is empty.
    final gate = widget.gate;
    if (gate != null && !await gate()) return;
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _QuizPhase.finished) {
      return ResultsScreen(
        gameTitle: widget.title,
        score: _score,
        total: _questions.length,
        goldEarned: _goldEarned,
        onPlayAgain: _playAgain,
        onBack: () => Navigator.pop(context),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: _phase == _QuizPhase.playing
            ? [
                Center(child: Text('${_index + 1}/${_questions.length}', style: AppTextStyles.numbersLg())),
                const SizedBox(width: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text('⭐ $_score', style: AppTextStyles.numbers.copyWith(color: AppColors.aniGold)),
                  ),
                ),
                const SizedBox(width: 16),
              ]
            : null,
      ),
      body: SafeArea(
        child: switch (_phase) {
          _QuizPhase.loading => _loadingView(),
          _QuizPhase.error => _errorView(),
          _ => _questionView(_questions[_index]),
        },
      ),
    );
  }

  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text('Loading questions…', style: AppTextStyles.bodyMuted),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 46, color: AppColors.textMuted),
          const SizedBox(height: 16),
          const Text("Couldn't load questions", style: AppTextStyles.heading, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text(
            'AniList may be busy or you may be offline. Try again in a moment.',
            style: AppTextStyles.bodyMuted,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: GradientButton(label: 'Try Again', onPressed: _load)),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _questionView(QuizQuestion q) {
    final hasImage = (q.imageUrl ?? '').isNotEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _timerBar(),
          const SizedBox(height: 18),
          _promptArea(q, hasImage),
          if (hasImage) ...[
            const SizedBox(height: 18),
            Text(q.question, style: AppTextStyles.heading, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 18),
          ...List.generate(q.options.length, (i) => _optionButton(q, i)),
        ],
      ),
    );
  }

  Widget _timerBar() {
    final color = _secondsLeft <= 5 ? AppColors.error : AppColors.accent;
    return Row(
      children: [
        Icon(LucideIcons.timer, size: 16, color: color),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          child: Text('${_secondsLeft}s', style: AppTextStyles.numbers.copyWith(color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _secondsLeft / _secondsPerQuestion,
              minHeight: 6,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }

  /// Character portrait when the question has an image; otherwise the question
  /// string itself is the prompt, rendered large (the Emoji Anime riddles).
  Widget _promptArea(QuizQuestion q, bool hasImage) {
    if (!hasImage) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          gradient: AppGradients.forSeed(q.question),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(q.question, textAlign: TextAlign.center, style: const TextStyle(fontSize: 52, height: 1.3)),
      );
    }
    return Center(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppGradients.pairForSeed(q.options[q.correctIndex]).last.withOpacity(0.4),
              blurRadius: 28,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            q.imageUrl!,
            width: 190,
            height: 250,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                width: 190,
                height: 250,
                color: AppColors.surfaceAlt,
                child: const Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primary),
                  ),
                ),
              );
            },
            // A failed image must never break the question — show a placeholder.
            errorBuilder: (context, error, stackTrace) => Container(
              width: 190,
              height: 250,
              color: AppColors.surfaceAlt,
              child: const Icon(Icons.broken_image_rounded, size: 44, color: AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionButton(QuizQuestion q, int i) {
    final isCorrect = i == q.correctIndex;
    Color? bg, border;
    if (_locked) {
      if (isCorrect) {
        bg = AppColors.success.withOpacity(0.18);
        border = AppColors.success;
      } else if (_picked == i) {
        bg = AppColors.error.withOpacity(0.18);
        border = AppColors.error;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _locked ? null : () => _answer(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: bg ?? AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border ?? AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(child: Text(q.options[i], style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600))),
              if (_locked && isCorrect) const Icon(LucideIcons.check, color: AppColors.success, size: 18),
              if (_locked && !isCorrect && _picked == i) const Icon(LucideIcons.x, color: AppColors.error, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
