import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../services/observatory_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import 'observatory_provider.dart';

/// Observatory — community numbers that actually have a source.
///
/// Every figure on this screen traces to a Firestore aggregation or an AniList
/// field. This screen previously shipped ten hardcoded values (1.2M "online",
/// 8.4M "episodes today", four invented regional splits) with no data source
/// behind any of them; all of it was deleted rather than re-plumbed.
///
/// Two rules this screen exists to hold:
///  - No presence. We cannot measure who is "online" or "watching now", so we
///    do not claim to. There is no live dot anywhere on this screen.
///  - No geography on global data. AniList popularity is one worldwide number
///    per title with no country breakdown, so it renders as a plainly-labelled
///    ranked list and never as a regional figure.
///
/// The country map is deliberately absent: at current scale no country clears
/// the 5-member privacy floor, so it would only ever render "not enough data".
/// The aggregation behind it (with the floor built in) already exists in
/// [ObservatoryService.fetchCountryBreakdown].
class ObservatoryScreen extends ConsumerWidget {
  const ObservatoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('observatory'))),
      body: RefreshIndicator(
        color: AppColors.primaryLight,
        backgroundColor: AppColors.surfaceAlt,
        onRefresh: () async {
          ref.invalidate(observatoryStatsProvider);
          ref.invalidate(globalPopularProvider);
          // Errors are swallowed HERE on purpose: each section already renders
          // its own error state with a Retry. Letting them escape onRefresh
          // would surface an unhandled framework error on every offline pull.
          await Future.wait([
            ref.read(observatoryStatsProvider.future).then<void>((_) {}, onError: (_, __) {}),
            ref.read(globalPopularProvider.future).then<void>((_) {}, onError: (_, __) {}),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
          children: const [
            _CommunitySection(),
            SizedBox(height: 26),
            _GlobalPopularSection(),
          ],
        ),
      ),
    );
  }
}

// ── Community — real Firestore aggregations ──────────────────────────────

class _CommunitySection extends ConsumerWidget {
  const _CommunitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(observatoryStatsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ref.tr('observatoryCommunity'), style: AppTextStyles.subheading),
        const SizedBox(height: 12),
        stats.when(
          loading: () => const _StatRowSkeleton(),
          error: (_, __) => _SectionError(
            message: ref.tr('observatoryStatsError'),
            onRetry: () => ref.invalidate(observatoryStatsProvider),
          ),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      // count() over `users`, unfiltered. NOT the sum of
                      // per-country counts — two docs carry no countryCode
                      // and equality filters skip them.
                      value: s.totalMembers,
                      label: ref.tr('observatoryMembers'),
                      icon: LucideIcons.users,
                      color: AppColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatTile(
                      // count() over `posts` where createdAt >= 00:00 UTC.
                      value: s.postsToday,
                      label: ref.tr('observatoryPostsToday'),
                      icon: LucideIcons.messageSquare,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(ref.tr('observatoryUtcNote'), style: AppTextStyles.captionMuted),
            ],
          ),
        ),
      ],
    );
  }
}

/// One sourced number. No count-up animation: the old screen animated invented
/// figures specifically to make them read as live telemetry.
class _StatTile extends StatelessWidget {
  final int value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Text(Fmt.compact(value), style: AppTextStyles.numbersXl(color: color)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.captionMuted),
        ],
      ),
    );
  }
}

// ── Global popularity — AniList, explicitly worldwide ────────────────────

class _GlobalPopularSection extends ConsumerWidget {
  const _GlobalPopularSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(globalPopularProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Visually separated from the community block above: this data has a
        // different source AND a different scope, and conflating the two is
        // exactly how a global number ends up implying a local one.
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 18),
        Text(ref.tr('observatoryGlobalTitle'), style: AppTextStyles.subheading),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(LucideIcons.globe, size: 13, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(ref.tr('observatoryGlobalNote'), style: AppTextStyles.captionMuted),
            ),
          ],
        ),
        const SizedBox(height: 14),
        popular.when(
          loading: () => const _ListSkeleton(),
          error: (_, __) => _SectionError(
            message: ref.tr('observatoryPopularError'),
            onRetry: () => ref.invalidate(globalPopularProvider),
          ),
          data: (list) => list.isEmpty
              ? Text(ref.tr('observatoryPopularEmpty'), style: AppTextStyles.bodyMuted)
              : Column(
                  children: [
                    for (var i = 0; i < list.length; i++)
                      _PopularRow(rank: i + 1, anime: list[i]),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PopularRow extends ConsumerWidget {
  final int rank;
  final PopularAnime anime;

  const _PopularRow({required this.rank, required this.anime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('$rank', style: AppTextStyles.numbersLg()),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 36,
              height: 44,
              child: anime.coverUrl.isEmpty
                  ? Container(color: AppColors.surfaceAlt)
                  : CachedNetworkImage(
                      imageUrl: anime.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceAlt),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  anime.title,
                  style: AppTextStyles.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // AniList Media.popularity — worldwide, no country dimension.
                Text(
                  '${Fmt.compact(anime.popularity)} · ${ref.tr('observatoryOnLists')}',
                  style: AppTextStyles.captionMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── States ───────────────────────────────────────────────────────────────

class _SectionError extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;

  const _SectionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.cloudOff, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
          const SizedBox(height: 16),
          GradientButton(label: ref.tr('retry'), expand: false, onPressed: onRetry),
        ],
      ),
    );
  }
}

class _StatRowSkeleton extends StatelessWidget {
  const _StatRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: _Block(height: 104)),
        SizedBox(width: 12),
        Expanded(child: _Block(height: 104)),
      ],
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _Block(height: 64),
          ),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  final double height;
  const _Block({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
    );
  }
}
