import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/anime_model.dart';
import '../../data/sample_data.dart';
import '../../shared/providers/user_provider.dart';
import '../../shared/widgets/anime_card.dart';
import '../../shared/widgets/anime_cover_image.dart';
import '../../shared/widgets/aniplus_paywall.dart';
import '../../shared/widgets/section_header.dart';

class AnimeDetailScreen extends ConsumerStatefulWidget {
  final String animeId;
  const AnimeDetailScreen({super.key, required this.animeId});
  @override
  ConsumerState<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends ConsumerState<AnimeDetailScreen> {
  WatchStatus? _status;
  double? _myScore;
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final anime = SampleData.animeById(widget.animeId);
    final isPlus = ref.watch(isPlusProvider);
    final palette = _palette(anime);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  AnimeCoverImage(animeName: anime.title, gradient: anime.gradient, emoji: anime.emoji, emojiSize: 120),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87], stops: [0.45, 1]),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(anime.title, style: AppTextStyles.display.copyWith(color: Colors.white)),
                        Text(anime.japaneseTitle, style: AppTextStyles.bodyMuted),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip(anime.studio, LucideIcons.building2),
                      _chip('${anime.year}', LucideIcons.calendar),
                      _chip('${anime.episodes} eps', LucideIcons.playCircle),
                      _statusChip(anime.status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.star_rounded, color: AppColors.aniGold, size: 28),
                            const SizedBox(width: 4),
                            Text(anime.score.toStringAsFixed(1), style: AppTextStyles.numbersXl()),
                          ]),
                          Text('${Fmt.compact(anime.ratingCount)} ratings', style: AppTextStyles.captionMuted),
                        ],
                      ),
                      const Spacer(),
                      if (anime.watchingNow > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                          child: Row(children: [
                            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text('${Fmt.compact(anime.watchingNow)} watching', style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
                          ]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _actions(anime, isPlus),
                  const SizedBox(height: 10),
                  Row(children: [
                    _watchOn('Crunchyroll', const Color(0xFFF47521)),
                    const SizedBox(width: 8),
                    _watchOn('Netflix', const Color(0xFFE50914)),
                  ]),
                  if (isPlus) ...[
                    const SizedBox(height: 16),
                    _predictorCard(anime),
                  ],
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SectionHeader(title: 'Episodes')),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _episodeRow(anime, i, isPlus),
              childCount: 6,
            ),
          ),
          SliverToBoxAdapter(child: _paletteSection(anime, palette)),
          SliverToBoxAdapter(child: _predictionsSection()),
          const SliverToBoxAdapter(child: SectionHeader(title: 'Similar anime')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: 6,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => AnimeCard(anime: SampleData.animeList[(i + 5) % SampleData.animeList.length]),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }

  Widget _actions(AnimeModel anime, bool isPlus) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                _status == null ? 'Add to List' : _status!.label,
                LucideIcons.plus,
                primary: true,
                onTap: () => _addToList(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionBtn(
                _myScore == null ? 'Rate' : '★ ${_myScore!.toInt()}/10',
                LucideIcons.star,
                onTap: () => _rate(isPlus),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _actionBtn(
          _following ? 'Following updates 🔔' : 'Follow updates',
          LucideIcons.bell,
          full: true,
          onTap: () {
            Haptics.light();
            setState(() => _following = !_following);
          },
        ),
      ],
    );
  }

  void _addToList() {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: WatchStatus.values.map((s) => ListTile(
                leading: Icon(_statusIcon(s), color: AppColors.primaryLight),
                title: Text(s.label, style: AppTextStyles.body),
                trailing: _status == s ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () {
                  Haptics.select();
                  setState(() => _status = s);
                  Navigator.pop(ctx);
                },
              )).toList(),
        ),
      ),
    );
  }

  void _rate(bool isPlus) {
    Haptics.light();
    double temp = _myScore ?? 8;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Rate this anime'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${temp.toInt()} / 10', style: AppTextStyles.numbersXl(color: AppColors.aniGold)),
              Slider(
                value: temp,
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: AppColors.primary,
                onChanged: (v) => setD(() => temp = v),
              ),
              Text(isPlus ? 'AniPlus: unlimited ratings' : 'Free: 5 ratings/day', style: AppTextStyles.captionMuted),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  if (!isPlus) {
                    Navigator.pop(ctx);
                    showAniPlusPaywall(context, 'Predict My Rating');
                  } else {
                    setD(() => temp = 8.3);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: AppGradients.brand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('🔮 Predict my rating', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                Haptics.medium();
                setState(() => _myScore = temp);
                Navigator.pop(ctx);
                if (isPlus) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✍️ AI review draft saved'), duration: Duration(seconds: 1)));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _predictorCard(AnimeModel anime) {
    final predicted = (anime.score - 0.4).clamp(0, 10);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.2), AppColors.accent.withOpacity(0.12)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🔮', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('Rating Predictor', style: AppTextStyles.subheading),
            Spacer(),
            PlusChip(),
          ]),
          const SizedBox(height: 10),
          Text('Based on your taste: ${predicted.toStringAsFixed(1)}/10', style: AppTextStyles.body),
          const SizedBox(height: 8),
          const Text('Confidence', style: AppTextStyles.captionMuted),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(value: 0.86, minHeight: 6, backgroundColor: AppColors.background, valueColor: AlwaysStoppedAnimation(AppColors.accent)),
          ),
        ],
      ),
    );
  }

  Widget _episodeRow(AnimeModel anime, int i, bool isPlus) {
    final ep = i + 1;
    final summaryFree = i == 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(gradient: anime.gradient, borderRadius: BorderRadius.circular(8)), alignment: Alignment.center, child: Text('$ep', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(child: Text('Episode $ep', style: AppTextStyles.label)),
          GestureDetector(
            onTap: () {
              if (summaryFree || isPlus) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Episode $ep summary'), duration: const Duration(seconds: 1)));
              } else {
                showAniPlusPaywall(context, 'AI Episode Summaries');
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: (summaryFree || isPlus) ? AppColors.border : AppColors.primary.withOpacity(0.5)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('📝 Summary', style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary)),
                if (!summaryFree && !isPlus) ...[const SizedBox(width: 4), const Icon(LucideIcons.lock, size: 11, color: AppColors.aniGold)],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paletteSection(AnimeModel anime, List<Color> palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: '🎨 Color Palette · ${anime.title}'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: palette.map((c) {
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    final hex = '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
                    Haptics.light();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$hex copied'),
                      duration: const Duration(seconds: 1),
                      action: SnackBarAction(label: 'Copy', onPressed: () => Clipboard.setData(ClipboardData(text: hex))),
                    ));
                    Clipboard.setData(ClipboardData(text: hex));
                  },
                  child: Container(height: 60, margin: const EdgeInsets.symmetric(horizontal: 3), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10))),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _predictionsSection() {
    final preds = [('Season 2 confirmed?', 0.78, 'Yes'), ('Will score 9+?', 0.64, 'Yes'), ('Enter Top 100?', 0.91, 'Yes')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '🔮 Community Predictions'),
        ...preds.map((p) => Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(p.$1, style: AppTextStyles.body)),
                    Text('${(p.$2 * 100).toInt()}% ${p.$3}', style: AppTextStyles.numbers.copyWith(color: AppColors.accent)),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: p.$2, minHeight: 8, backgroundColor: AppColors.surface, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  // helpers
  Widget _chip(String label, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: AppColors.textSecondary), const SizedBox(width: 5), Text(label, style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary))]),
      );

  Widget _statusChip(String status) {
    final airing = status == 'Airing';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: (airing ? AppColors.success : AppColors.textMuted).withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: (airing ? AppColors.success : AppColors.textMuted).withOpacity(0.5))),
      child: Text(status, style: AppTextStyles.caption.copyWith(color: airing ? AppColors.success : AppColors.textSecondary, fontWeight: FontWeight.w700)),
    );
  }

  Widget _actionBtn(String label, IconData icon, {bool primary = false, bool full = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: full ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: primary ? AppGradients.brand : null,
          color: primary ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: primary ? Colors.transparent : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5))),
        ]),
      ),
    );
  }

  Widget _watchOn(String name, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.6))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(LucideIcons.play, size: 14, color: color),
            const SizedBox(width: 6),
            Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
      );

  IconData _statusIcon(WatchStatus s) => switch (s) {
        WatchStatus.watching => LucideIcons.play,
        WatchStatus.completed => LucideIcons.checkCircle,
        WatchStatus.planning => LucideIcons.bookmark,
        WatchStatus.onHold => LucideIcons.pause,
        WatchStatus.dropped => LucideIcons.x,
      };

  List<Color> _palette(AnimeModel a) {
    final p = a.gradientColors;
    return [
      p[0],
      Color.lerp(p[0], p[1], 0.5)!,
      p[1],
      AppColors.accent,
      AppColors.aniGold,
    ];
  }
}
