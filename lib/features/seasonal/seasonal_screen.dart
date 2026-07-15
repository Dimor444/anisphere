import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/anilist_season.dart';
import '../../core/utils/haptics.dart';
import '../../services/seasonal_service.dart';
import '../../services/trending_service.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/pressable.dart';
import 'seasonal_provider.dart';

/// Seasonal — the current season's airing schedule, live from AniList,
/// grouped by local weekday with today highlighted.
class SeasonalScreen extends ConsumerWidget {
  const SeasonalScreen({super.key});

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(seasonalScheduleProvider);
    final s = aniListSeasonOf(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seasonal'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 0, 10),
              child: Text(
                '${seasonEmoji(s.season)} ${seasonDisplayName(s.season)} ${s.year}',
                style: AppTextStyles.bodyMuted,
              ),
            ),
          ),
        ),
      ),
      body: schedule.when(
        loading: () => const _SeasonalSkeleton(),
        error: (_, __) => _SeasonalError(onRetry: () => ref.invalidate(seasonalScheduleProvider)),
        data: (sched) => sched.isEmpty
            ? const _SeasonalEmpty()
            : RefreshIndicator(
                onRefresh: () => ref.refresh(seasonalScheduleProvider.future),
                color: AppColors.primaryLight,
                backgroundColor: AppColors.surfaceAlt,
                child: _DaySections(schedule: sched),
              ),
      ),
    );
  }
}

/// Vertical Mon–Sun sections: a day pill, then that day's shows as a
/// horizontal rail. Only days with airing episodes are rendered.
class _DaySections extends StatelessWidget {
  final SeasonalSchedule schedule;
  const _DaySections({required this.schedule});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    final days = [
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        if (schedule.byWeekday.containsKey(d)) d,
    ];

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 90),
      itemCount: days.length,
      itemBuilder: (_, i) {
        final day = days[i];
        final isToday = day == today;
        final anime = schedule.byWeekday[day]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isToday ? AppColors.primary : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isToday ? AppColors.primary : AppColors.border),
                ),
                child: Text(
                  isToday ? '${SeasonalScreen._days[day - 1]} · Today' : SeasonalScreen._days[day - 1],
                  style: AppTextStyles.subheading.copyWith(color: isToday ? Colors.white : AppColors.textPrimary),
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: anime.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, j) => _SeasonalCard(anime: anime[j]),
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

class _SeasonalCard extends StatelessWidget {
  final SeasonalAnime anime;
  const _SeasonalCard({required this.anime});

  @override
  Widget build(BuildContext context) {
    // Cards only render from weekday groups, so nextAiringAt is never null here.
    final time = DateFormat('HH:mm').format(anime.nextAiringAt!.toLocal());

    return Pressable(
      onTap: () {
        Haptics.light();
        // AniList-referenced entry — partial extra paints the header
        // instantly; the detail screen fetches the full record by id.
        // Never route through '/anime/:id' (keyed to local sample data).
        context.push(
          '/trending/anime/${anime.id}',
          extra: TrendingAnime(
            id: anime.id,
            title: anime.title,
            coverUrl: anime.coverUrl,
            description: '',
            genres: const [],
            status: '',
            score: 0,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              anime.coverUrl.isEmpty
                  ? DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(anime.title)))
                  : CachedNetworkImage(
                      imageUrl: anime.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                      errorWidget: (_, __, ___) =>
                          DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(anime.title))),
                    ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black26, Colors.black87],
                      stops: [0.2, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reminder bell — placeholder for now, kept from the old design.
                    Row(children: [
                      const Spacer(),
                      GestureDetector(onTap: () => Haptics.light(), child: const Icon(LucideIcons.bell, size: 16, color: Colors.white)),
                    ]),
                    const Spacer(),
                    Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.label.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Ep ${anime.nextEpisode} · $time', style: AppTextStyles.caption.copyWith(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shimmer placeholder mimicking two day sections while the first load runs.
class _SeasonalSkeleton extends StatelessWidget {
  const _SeasonalSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceAlt,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 90),
        children: [
          for (var s = 0; s < 3; s++) ...[
            Container(
              width: 90,
              height: 36,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            ),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  for (var c = 0; c < 3; c++)
                    Container(
                      width: 150,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _SeasonalError extends StatelessWidget {
  final VoidCallback onRetry;
  const _SeasonalError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.cloudOff, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            const Text(
              "Couldn't load the seasonal schedule.\nCheck your connection and try again.",
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 18),
            GradientButton(label: 'Retry', expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _SeasonalEmpty extends StatelessWidget {
  const _SeasonalEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.calendarOff, size: 44, color: AppColors.textMuted),
            SizedBox(height: 14),
            Text('No episodes airing this week.', style: AppTextStyles.bodyMuted),
          ],
        ),
      ),
    );
  }
}
