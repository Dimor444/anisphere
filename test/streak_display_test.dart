import 'package:anisphere/services/streak_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreakService.displayStreak', () {
    // Fixed reference: 2026-07-09 (UTC noon avoids any boundary ambiguity).
    final now = DateTime.utc(2026, 7, 9, 12);

    test('checked in today → shows the stored streak', () {
      expect(StreakService.displayStreak(currentStreak: 5, lastActiveDay: '2026-07-09', now: now), 5);
    });

    test('checked in yesterday → still alive, shows the stored streak', () {
      expect(StreakService.displayStreak(currentStreak: 5, lastActiveDay: '2026-07-08', now: now), 5);
    });

    test('lapsed (older than yesterday) → displays 0, stored value untouched', () {
      expect(StreakService.displayStreak(currentStreak: 5, lastActiveDay: '2026-07-06', now: now), 0);
    });

    test('never checked in → 0', () {
      expect(StreakService.displayStreak(currentStreak: 0, lastActiveDay: '', now: now), 0);
    });

    test('month/year boundaries compare correctly (string days, UTC)', () {
      final jan1 = DateTime.utc(2027, 1, 1, 3);
      expect(StreakService.displayStreak(currentStreak: 12, lastActiveDay: '2026-12-31', now: jan1), 12);
      expect(StreakService.displayStreak(currentStreak: 12, lastActiveDay: '2026-12-30', now: jan1), 0);
    });
  });
}
