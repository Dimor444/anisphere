import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/trending_service.dart';
import '../../shared/providers/language_provider.dart';

/// An anime's title and cover from AniList, by id — what the vote board, a
/// player's own votes and the vote history show. Never the title and cover
/// written into a tally or a vote: any voter can rewrite a tally's, within
/// the rules' format checks. Null when AniList answered without the id —
/// filtered as adult, or no longer there.
///
/// Ids asked for together go to AniList in one batched request, and answers
/// are kept for the session ([TrendingService.briefById]). autoDispose, so a
/// lookup that failed is tried again the next time the screen opens.
final voteAnimeProvider = FutureProvider.autoDispose.family<TrendingAnime?, int>(
  (ref, anilistId) => TrendingService.instance.briefById(anilistId),
);

/// Builds with [anilistId]'s title and cover as AniList has them: "…" and no
/// cover while loading or when AniList cannot be reached, and "Title
/// unavailable" with no cover when AniList left the id out — the row keeps
/// its rank and votes, which are real, but nothing a voter wrote is shown.
class VoteAnime extends ConsumerWidget {
  final int anilistId;
  final Widget Function(BuildContext context, String title, String coverUrl) builder;
  const VoteAnime({super.key, required this.anilistId, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anime = ref.watch(voteAnimeProvider(anilistId));
    final title = switch (anime) {
      AsyncData(value: final a?) => a.title,
      AsyncData() => ref.tr('titleUnavailable'),
      _ => '…',
    };
    return builder(context, title, anime.valueOrNull?.coverUrl ?? '');
  }
}
