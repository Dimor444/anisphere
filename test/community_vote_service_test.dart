import 'package:anisphere/services/community_vote_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommunityVoteService day math', () {
    test('dayIdFor is the UTC date, zero-padded and sortable', () {
      expect(CommunityVoteService.dayIdFor(DateTime.utc(2026, 7, 6, 23, 59)), '2026-07-06');
      expect(CommunityVoteService.dayIdFor(DateTime.utc(2026, 1, 1)), '2026-01-01');
      expect(CommunityVoteService.dayIdFor(DateTime.utc(2026, 12, 31, 0, 0, 1)), '2026-12-31');
    });

    test('dayIdFor converts local times to the UTC day', () {
      // 01:00+02:00 on Jul 7 is still 23:00 UTC on Jul 6.
      final local = DateTime.parse('2026-07-07T01:00:00+02:00');
      expect(CommunityVoteService.dayIdFor(local), '2026-07-06');
    });

    test('untilNextResetFrom counts down to 00:00 UTC', () {
      expect(
        CommunityVoteService.untilNextResetFrom(DateTime.utc(2026, 7, 6, 17, 18)),
        const Duration(hours: 6, minutes: 42),
      );
      expect(
        CommunityVoteService.untilNextResetFrom(DateTime.utc(2026, 7, 6)),
        const Duration(days: 1), // exactly at reset → full day ahead
      );
    });

    test('vote allowance: 1 free, 4 for AniPlus', () {
      expect(CommunityVoteService.getMaxVotesForUser(isPlus: false), 1);
      expect(CommunityVoteService.getMaxVotesForUser(isPlus: true), 4);
    });
  });
}
