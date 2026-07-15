import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/anime_cover_image.dart';

class ObservatoryScreen extends StatelessWidget {
  const ObservatoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final regions = [
      ('🇯🇵 Asia', 4820000, AppColors.primary),
      ('🇺🇸 Americas', 3210000, AppColors.accent),
      ('🇸🇦 MENA', 1740000, AppColors.aniGold),
      ('🇪🇺 Europe', 2980000, AppColors.secondary),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('🌍 Observatory')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(children: [
            Expanded(child: _counter('Watching now', 184203, AppColors.success)),
            const SizedBox(width: 12),
            Expanded(child: _counter('Online', 1240880, AppColors.accent)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _counter('Episodes today', 8421033, AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(child: _counter('Posts today', 320145, AppColors.secondary)),
          ]),
          const SizedBox(height: 20),
          const Text('Live by region', style: AppTextStyles.subheading),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.5),
            itemCount: regions.length,
            itemBuilder: (_, i) {
              final r = regions[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [r.$3.withOpacity(0.3), r.$3.withOpacity(0.08)]), borderRadius: BorderRadius.circular(16), border: Border.all(color: r.$3.withOpacity(0.5))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(r.$1, style: AppTextStyles.subheading),
                  Text(Fmt.compact(r.$2), style: AppTextStyles.numbersXl(color: r.$3)),
                ]),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text('🔥 Top 10 right now', style: AppTextStyles.subheading),
          const SizedBox(height: 12),
          ...SampleData.chart.asMap().entries.map((e) {
            final anime = SampleData.animeByTitle(e.value.title);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${e.key + 1}', style: AppTextStyles.numbersLg())),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 36, height: 44, child: AnimeCoverImage(animeName: anime.title, gradient: anime.gradient, emoji: anime.emoji, emojiSize: 18))),
                const SizedBox(width: 12),
                Expanded(child: Text(e.value.title, style: AppTextStyles.label)),
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(Fmt.compact(40000 - e.key * 2800), style: AppTextStyles.numbers.copyWith(color: AppColors.success)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _counter(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOut,
            builder: (_, v, __) => Text(Fmt.compact(v.round()), style: AppTextStyles.numbersXl(color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.captionMuted),
        ],
      ),
    );
  }
}
