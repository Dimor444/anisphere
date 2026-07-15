import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/community_vote.dart';
import '../../services/community_vote_service.dart';
import '../../shared/providers/language_provider.dart';

/// Past community-vote days (`/community-vote/history`): one card per day
/// with that day's winner; tap for the full final leaderboard. Past days are
/// immutable — nothing ever writes to an old dayId.
class CommunityVoteHistoryScreen extends ConsumerWidget {
  const CommunityVoteHistoryScreen({super.key});

  static const int _daysBack = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now().toUtc();
    final days = List.generate(
      _daysBack,
      (i) => CommunityVoteService.dayIdFor(today.subtract(Duration(days: i + 1))),
    );
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('pastVotesTitle'))),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
          itemCount: days.length,
          itemBuilder: (_, i) => _DayCard(dayId: days[i]),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final String dayId;
  const _DayCard({required this.dayId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CommunityVoteTally>>(
      // Winner preview only needs the top entry.
      future: CommunityVoteService.instance.getPastDayLeaderboard(dayId, limit: 1),
      builder: (context, snap) {
        final winner = (snap.data?.isNotEmpty ?? false) ? snap.data!.first : null;
        // Days with no votes at all are skipped once known.
        if (snap.hasData && winner == null) return const SizedBox.shrink();
        final date = DateFormat('MMM d, yyyy').format(DateTime.parse(dayId));
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: winner == null
                ? null
                : () {
                    Haptics.light();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _PastDayScreen(dayId: dayId, dateLabel: date)),
                    );
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(date, style: AppTextStyles.captionMuted),
                        Text(
                          winner?.animeTitle ?? '…',
                          style: AppTextStyles.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (winner != null) Text('${winner.voteCount}', style: AppTextStyles.numbers),
                  const SizedBox(width: 6),
                  const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Final (read-only) leaderboard for one past day.
class _PastDayScreen extends StatelessWidget {
  final String dayId;
  final String dateLabel;
  const _PastDayScreen({required this.dayId, required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(dateLabel)),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: FutureBuilder<List<CommunityVoteTally>>(
          future: CommunityVoteService.instance.getPastDayLeaderboard(dayId),
          builder: (context, snap) {
            final board = snap.data;
            if (board == null) return const Center(child: CircularProgressIndicator());
            final total = board.fold(0, (n, t) => n + t.voteCount);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
              itemCount: board.length,
              itemBuilder: (_, i) {
                final t = board[i];
                final first = i == 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: first ? AppColors.aniGold : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 26,
                          child: Text(first ? '🏆' : '${i + 1}',
                              textAlign: TextAlign.center, style: AppTextStyles.numbersLg())),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(t.animeTitle, style: AppTextStyles.label, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        total == 0 ? '${t.voteCount}' : '${t.voteCount} · ${(t.voteCount * 100 / total).round()}%',
                        style: AppTextStyles.numbers,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
