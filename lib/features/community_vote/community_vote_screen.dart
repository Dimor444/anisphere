import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/community_vote.dart';
import '../../services/community_vote_service.dart';
import '../../services/trending_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/aniplus_paywall.dart';
import '../../shared/widgets/gradient_button.dart';

/// Routed wrapper (`/community-vote`) around the vote body.
class CommunityVoteScreen extends ConsumerWidget {
  const CommunityVoteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('communityVoteTitle'))),
      body: const DecoratedBox(
        decoration: BoxDecoration(gradient: AppGradients.pageBg),
        child: CommunityVoteBody(),
      ),
    );
  }
}

/// The daily community vote: status, cast flow, your votes, live leaderboard.
/// Embedded both as a Discover tab and inside [CommunityVoteScreen].
class CommunityVoteBody extends ConsumerStatefulWidget {
  const CommunityVoteBody({super.key});

  @override
  ConsumerState<CommunityVoteBody> createState() => _CommunityVoteBodyState();
}

class _CommunityVoteBodyState extends ConsumerState<CommunityVoteBody> {
  // Streams created once — never re-instantiated on rebuild (single-sub).
  late final Stream<List<CommunityVote>> _myVotes =
      CommunityVoteService.instance.getUserVotesToday();
  late final Stream<List<CommunityVoteTally>> _board =
      CommunityVoteService.instance.getDailyLeaderboard();
  bool _casting = false;

  Future<void> _startCastFlow(List<CommunityVote> votes, bool isPlus) async {
    if (_casting) return;
    Haptics.light();
    final max = CommunityVoteService.getMaxVotesForUser(isPlus: isPlus);
    if (votes.length >= max) {
      _snack('${ref.tr('noVotesLeftToday')} · ${ref.tr('resetsIn')} ${_fmtReset()}');
      return;
    }

    final picked = await showModalBottomSheet<TrendingAnime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _VoteSearchSheet(),
    );
    if (picked == null || !mounted) return;

    if (votes.any((v) => v.anilistId == picked.id)) {
      _snack(ref.tr('alreadyVotedToday'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('${ref.tr('voteForConfirm')} ${picked.title}?', style: AppTextStyles.subheading),
        content: Text(ref.tr('cantBeUndone'), style: AppTextStyles.bodyMuted),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: Text(ref.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: Text(ref.tr('vote'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _casting = true);
    try {
      await CommunityVoteService.instance.castVote(
        anilistId: picked.id,
        animeTitle: picked.title,
        animeCover: picked.coverUrl,
        isPlus: isPlus,
      );
      Haptics.medium();
      _snack(ref.tr('voteCastSuccess'));
    } on AlreadyVotedTodayException {
      _snack(ref.tr('alreadyVotedToday'));
    } on VoteLimitReachedException {
      _snack(ref.tr('noVotesLeftToday'));
    } catch (_) {
      _snack(ref.tr('listError'));
    } finally {
      if (mounted) setState(() => _casting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  String _fmtReset() {
    final d = CommunityVoteService.instance.untilNextReset();
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final isPlus = ref.watch(userProvider).isPlusUser;
    return StreamBuilder<List<CommunityVote>>(
      stream: _myVotes,
      builder: (context, votesSnap) {
        final votes = votesSnap.data ?? const <CommunityVote>[];
        final max = CommunityVoteService.getMaxVotesForUser(isPlus: isPlus);
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
          children: [
            Row(
              children: [
                Expanded(child: Text('🗳️ ${ref.tr('communityVoteTitle')}', style: AppTextStyles.heading)),
                const _CountdownChip(),
              ],
            ),
            const SizedBox(height: 12),
            _statusCard(votes, max, isPlus),
            const SizedBox(height: 12),
            GradientButton(
              label: ref.tr('castVote'),
              icon: LucideIcons.vote,
              onPressed: _casting ? null : () => _startCastFlow(votes, isPlus),
            ),
            if (votes.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(ref.tr('yourVotesToday'), style: AppTextStyles.subheading),
              const SizedBox(height: 8),
              // Read-only by design: votes are final, so no remove affordance.
              ...votes.map((v) => _myVoteRow(v)),
            ],
            const SizedBox(height: 20),
            Text('🏆 ${ref.tr('todaysLeaderboard')}', style: AppTextStyles.subheading),
            const SizedBox(height: 8),
            StreamBuilder<List<CommunityVoteTally>>(
              stream: _board,
              builder: (context, snap) {
                final board = snap.data;
                if (board == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (board.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                        child: Text(ref.tr('noVotesYetToday'), style: AppTextStyles.captionMuted)),
                  );
                }
                final total = board.fold(0, (n, t) => n + t.voteCount);
                final mine = votes.map((v) => v.anilistId).toSet();
                return Column(
                  children: [
                    for (var i = 0; i < board.length; i++)
                      _LeaderboardRow(
                        rank: i + 1,
                        tally: board[i],
                        share: total == 0 ? 0 : board[i].voteCount / total,
                        votedByMe: mine.contains(board[i].anilistId),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Haptics.light();
                  context.push('/community-vote/history');
                },
                icon: const Icon(LucideIcons.history, size: 16, color: AppColors.primaryLight),
                label: Text(ref.tr('viewPastDays'),
                    style: AppTextStyles.label.copyWith(color: AppColors.primaryLight)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statusCard(List<CommunityVote> votes, int max, bool isPlus) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Slot pips — Plus-only slots carry the gold accent.
          ...List.generate(max, (i) {
            final used = i < votes.length;
            final plusSlot = i >= CommunityVoteService.freeVotes;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                used ? Icons.how_to_vote_rounded : Icons.circle_outlined,
                size: used ? 20 : 16,
                color: used
                    ? (plusSlot ? AppColors.aniGold : AppColors.primaryLight)
                    : AppColors.textMuted,
              ),
            );
          }),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${ref.tr('votesRemaining')}: ${max - votes.length}/$max',
              style: AppTextStyles.label,
            ),
          ),
          if (!isPlus)
            GestureDetector(
              onTap: () {
                Haptics.light();
                showAniPlusPaywall(context, 'Community Vote');
              },
              child: Text(
                ref.tr('upgradeForVotes'),
                textAlign: TextAlign.end,
                style: AppTextStyles.caption.copyWith(color: AppColors.aniGold, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _myVoteRow(CommunityVote v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          _Cover(url: v.animeCover, seed: v.animeTitle, width: 34, height: 44),
          const SizedBox(width: 10),
          Expanded(child: Text(v.animeTitle, style: AppTextStyles.label, overflow: TextOverflow.ellipsis)),
          Icon(
            Icons.how_to_vote_rounded,
            size: 17,
            color: v.voteSlot > CommunityVoteService.freeVotes ? AppColors.aniGold : AppColors.primaryLight,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideX(begin: 0.05, end: 0);
  }
}

/// Live "Resets in 6h 42m" chip — ticks every 30s.
class _CountdownChip extends ConsumerStatefulWidget {
  const _CountdownChip();
  @override
  ConsumerState<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends ConsumerState<_CountdownChip> {
  late final Timer _tick =
      Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = CommunityVoteService.instance.untilNextReset();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(LucideIcons.timer, size: 13, color: AppColors.accent),
        const SizedBox(width: 5),
        Text('${ref.tr('resetsIn')} ${d.inHours}h ${d.inMinutes % 60}m', style: AppTextStyles.caption),
      ]),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final CommunityVoteTally tally;
  final double share; // 0..1 of today's votes
  final bool votedByMe;
  const _LeaderboardRow(
      {required this.rank, required this.tally, required this.share, required this.votedByMe});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: votedByMe ? AppColors.primary : AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text('$rank', textAlign: TextAlign.center, style: AppTextStyles.numbersLg())),
          const SizedBox(width: 8),
          _Cover(url: tally.animeCover, seed: tally.animeTitle, width: 40, height: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(tally.animeTitle,
                        style: AppTextStyles.label, overflow: TextOverflow.ellipsis),
                  ),
                  if (votedByMe) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.how_to_vote_rounded, size: 14, color: AppColors.primaryLight),
                  ],
                ]),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: share,
                    minHeight: 5,
                    backgroundColor: AppColors.background,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('${tally.voteCount}', style: AppTextStyles.numbers),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String url;
  final String seed;
  final double width;
  final double height;
  const _Cover({required this.url, required this.seed, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(seed)))
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                errorWidget: (_, __, ___) =>
                    DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(seed))),
              ),
      ),
    );
  }
}

/// Bottom sheet: debounced AniList search, tap a result to pick it.
class _VoteSearchSheet extends ConsumerStatefulWidget {
  const _VoteSearchSheet();
  @override
  ConsumerState<_VoteSearchSheet> createState() => _VoteSearchSheetState();
}

class _VoteSearchSheetState extends ConsumerState<_VoteSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  List<TrendingAnime>? _results;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final seq = ++_seq;
      try {
        final results = await TrendingService.instance.searchAnime(q);
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = results;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || seq != _seq) return;
        setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: TextField(
                key: const ValueKey('vote-search'),
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: ref.tr('searchAnimeHint'),
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  isDense: true,
                ),
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: results == null
                  ? Center(child: Text(ref.tr('searchAnimeHint'), style: AppTextStyles.captionMuted))
                  : results.isEmpty
                      ? Center(
                          child: Text('${ref.tr('noAnimeFound')} "${_ctrl.text.trim()}"',
                              style: AppTextStyles.captionMuted))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final a = results[i];
                            return InkWell(
                              onTap: () {
                                Haptics.light();
                                Navigator.pop(context, a);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                child: Row(
                                  children: [
                                    _Cover(url: a.coverUrl, seed: a.title, width: 36, height: 46),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(a.title, style: AppTextStyles.label, overflow: TextOverflow.ellipsis),
                                          if (a.seasonYear != null)
                                            Text('${a.seasonYear}', style: AppTextStyles.captionMuted),
                                        ],
                                      ),
                                    ),
                                    if (a.score > 0) ...[
                                      const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 14),
                                      Text(a.score.toStringAsFixed(1), style: AppTextStyles.captionMuted),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
