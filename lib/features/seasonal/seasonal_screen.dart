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
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/pressable.dart';
import 'seasonal_provider.dart';

/// This Week — the next 7 days of broadcasts, live from AniList's airing
/// schedule, grouped by local weekday with today highlighted.
///
/// The season is a subtitle, not a filter: filtering on `season`/`seasonYear`
/// excluded every long-running series, because those fields describe when a
/// show PREMIERED, not what is airing now.
class SeasonalScreen extends ConsumerWidget {
  const SeasonalScreen({super.key});

  /// Weekday (DateTime.monday=1 … sunday=7) → translation key.
  static const _dayKeys = ['dayMon', 'dayTue', 'dayWed', 'dayThu', 'dayFri', 'daySat', 'daySun'];

  static String dayLabel(WidgetRef ref, int weekday) => ref.tr(_dayKeys[weekday - 1]);

  static String seasonLabel(WidgetRef ref, String season) => switch (season) {
        'WINTER' => ref.tr('seasonWinter'),
        'SPRING' => ref.tr('seasonSpring'),
        'SUMMER' => ref.tr('seasonSummer'),
        _ => ref.tr('seasonFall'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(weeklyScheduleProvider);
    final s = aniListSeasonOf(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(ref.tr('thisWeek')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 0, 10),
              child: Text(
                '${seasonEmoji(s.season)} ${seasonLabel(ref, s.season)} ${s.year}',
                style: AppTextStyles.bodyMuted,
              ),
            ),
          ),
        ),
      ),
      body: schedule.when(
        loading: () => const _SeasonalSkeleton(),
        error: (_, __) => _SeasonalError(onRetry: () => ref.invalidate(weeklyScheduleProvider)),
        data: (sched) => sched.isEmpty
            ? const _SeasonalEmpty()
            : RefreshIndicator(
                onRefresh: () => ref.refresh(weeklyScheduleProvider.future),
                color: AppColors.primaryLight,
                backgroundColor: AppColors.surfaceAlt,
                child: _DaySections(schedule: sched),
              ),
      ),
    );
  }
}

/// Vertical Mon–Sun sections: a day pill, then that day's airings as a
/// horizontal rail. Only days with episodes are rendered.
class _DaySections extends ConsumerWidget {
  final WeeklySchedule schedule;
  const _DaySections({required this.schedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        final airings = schedule.byWeekday[day]!;
        final label = SeasonalScreen.dayLabel(ref, day);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 14, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isToday ? AppColors.primary : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isToday ? AppColors.primary : AppColors.border),
                ),
                child: Text(
                  isToday ? '$label · ${ref.tr('today')}' : label,
                  style: AppTextStyles.subheading.copyWith(color: isToday ? Colors.white : AppColors.textPrimary),
                ),
              ),
            ),
            SizedBox(
              height: 200,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: airings.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                // One card PER AIRING: a show broadcasting twice this week
                // has two entries and appears under both days.
                itemBuilder: (_, j) => _AiringCard(airing: airings[j]),
              ),
            ),
            const SizedBox(height: 14),
          ],
        );
      },
    );
  }
}

class _AiringCard extends ConsumerWidget {
  final AiringEntry airing;
  const _AiringCard({required this.airing});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = DateFormat('HH:mm').format(airing.airingAt.toLocal());

    return Pressable(
      onTap: () {
        Haptics.light();
        // AniList-referenced entry — partial extra paints the header
        // instantly; the detail screen fetches the full record by id.
        // Never route through '/anime/:id' (keyed to local sample data).
        context.push(
          '/trending/anime/${airing.mediaId}',
          extra: TrendingAnime(
            id: airing.mediaId,
            title: airing.title,
            coverUrl: airing.coverUrl,
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
              airing.coverUrl.isEmpty
                  ? DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(airing.title)))
                  : CachedNetworkImage(
                      imageUrl: airing.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: AppColors.surfaceAlt),
                      errorWidget: (_, __, ___) =>
                          DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(airing.title))),
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
                    Text(airing.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.label.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('${ref.tr('epShort')} ${airing.episode} · $time',
                        style: AppTextStyles.caption.copyWith(color: Colors.white70)),
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
              margin: const EdgeInsetsDirectional.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            ),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  for (var c = 0; c < 3; c++)
                    Container(
                      width: 150,
                      margin: const EdgeInsetsDirectional.only(end: 10),
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

class _SeasonalError extends ConsumerWidget {
  final VoidCallback onRetry;
  const _SeasonalError({required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.cloudOff, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              ref.tr('weekScheduleError'),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 18),
            GradientButton(label: ref.tr('retry'), expand: false, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _SeasonalEmpty extends ConsumerWidget {
  const _SeasonalEmpty();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.calendarOff, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(ref.tr('noEpisodesThisWeek'), style: AppTextStyles.bodyMuted),
          ],
        ),
      ),
    );
  }
}
