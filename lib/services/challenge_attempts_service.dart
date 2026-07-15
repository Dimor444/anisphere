import 'package:shared_preferences/shared_preferences.dart';

/// A single daily pool of challenge attempts shared across ALL challenge types
/// (the Games tab and the True Fan tab). Persisted in SharedPreferences and
/// reset automatically at midnight — i.e. whenever the stored date no longer
/// matches today.
///
/// Usage: `ChallengeAttemptsService().consumeAttempt()` (factory returns the
/// shared singleton).
class ChallengeAttemptsService {
  ChallengeAttemptsService._internal();
  static final ChallengeAttemptsService _instance = ChallengeAttemptsService._internal();
  factory ChallengeAttemptsService() => _instance;
  static ChallengeAttemptsService get instance => _instance;

  static const int maxDailyAttempts = 4;
  static const String _countKey = 'challenge_attempts_count';
  static const String _dateKey = 'challenge_attempts_date';

  /// Today's date as yyyy-MM-dd (local time).
  String _today() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Number of attempts used today. If the stored date isn't today, the count
  /// is reset to 0 and today's date is saved before returning.
  Future<int> getAttemptsUsedToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _today();
    if (prefs.getString(_dateKey) != today) {
      await prefs.setInt(_countKey, 0);
      await prefs.setString(_dateKey, today);
      return 0;
    }
    return prefs.getInt(_countKey) ?? 0;
  }

  /// Attempts remaining today (MAX − used). Triggers a daily reset if needed.
  Future<int> getRemainingAttempts() async => maxDailyAttempts - await getAttemptsUsedToday();

  /// Spends one attempt. Returns false (changing nothing) when none remain;
  /// otherwise increments the daily count, persists it, and returns true.
  Future<bool> consumeAttempt() async {
    if (await getRemainingAttempts() <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_countKey, (prefs.getInt(_countKey) ?? 0) + 1);
    return true;
  }
}
