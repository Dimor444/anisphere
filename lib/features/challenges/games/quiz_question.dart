/// A single multiple-choice question used by every Games-tab mini-game.
///
/// Immutable by design: loaders must build the complete question list —
/// including every [imageUrl] — before returning it to the UI. Questions are
/// never mutated after the quiz starts (a mutated-after-build imageUrl was the
/// cause of a previous blank-image bug).
class QuizQuestion {
  final String question;

  /// Optional prompt image (character portrait). When null, [question] itself
  /// is rendered as a large prompt (e.g. the Emoji Anime riddle).
  final String? imageUrl;

  /// 3 or 4 answer choices (True Fan uses 3; the Games-tab mini-games use 4).
  final List<String> options;

  /// Index into [options] of the correct answer.
  final int correctIndex;

  const QuizQuestion({
    required this.question,
    this.imageUrl,
    required this.options,
    required this.correctIndex,
  })  : assert(options.length == 3 || options.length == 4, 'A quiz question needs 3 or 4 options'),
        assert(correctIndex >= 0 && correctIndex < options.length);
}
