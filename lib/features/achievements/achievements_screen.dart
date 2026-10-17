import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/glass_modals.dart';

/// Whether Achievements exists at all: the `/achievements` route and the
/// drawer's link to it, the only two ways in.
///
/// Nothing on the screen was the player's. "8 / 12 unlocked", the unlock
/// dates going back to 2014 and every progress bar came from SampleData,
/// shown the same to every player — "Reach 1,000 followers" and "Maintain a
/// 30-day streak" unlocked on accounts with neither.
///
/// Five of the twelve have no source at all: nothing records episodes
/// watched per day (Binge Master) or the hour they were watched (Night
/// Owl), there are no reviews (Critic), card pulls are client-side samples
/// (Gacha God), and only the current language is kept, on the device
/// (Polyglot). The other seven could be computed from what is stored — True
/// Fan only partly, since a pass is kept only when it is faster, with its
/// own score — but not dated, since nothing records when a condition was
/// first met. And computed on the device they would un-unlock: a lost
/// follower, a deleted video, someone else passing faster, or a faster but
/// lower-scoring pass replacing a perfect one would take back what the
/// screen had called an achievement. Only the longest streak never drops.
///
/// Coming back needs achievements recorded server-side: a function that sees
/// each source change, checks the condition, and writes
/// users/{uid}/achievements/{id} once with a server timestamp — not
/// client-writable, never rewritten or deleted — which this screen reads in
/// place of SampleData. That gives real dates and unlocks that stay.
/// Followers should be counted from users/{uid}/followers, not
/// followerCount, which any signed-in user can move. An achievement with no
/// source needs one, or leaves the catalogue. The screen is kept, not
/// deleted.
const bool kAchievementsEnabled = false;

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});
  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  String _cat = 'All';
  final _cats = ['All', 'Social', 'Watching', 'Competitive', 'Creator'];

  @override
  Widget build(BuildContext context) {
    final items = SampleData.achievements.where((a) => _cat == 'All' || a.category == _cat).toList();
    final unlocked = SampleData.achievements.where((a) => a.unlocked).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(gradient: AppGradients.brandTri, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const Text('🏆', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(child: Text('$unlocked / ${SampleData.achievements.length} unlocked', style: AppTextStyles.subheading.copyWith(color: AppGradients.onFill(AppGradients.brandTri.colors.first)))),
                Text('${((unlocked / SampleData.achievements.length) * 100).round()}%', style: AppTextStyles.numbersLg(color: AppGradients.onFill(AppGradients.brandTri.colors.first))),
              ]),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: _cats.map((c) {
                final sel = c == _cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: sel,
                    onSelected: (_) {
                      Haptics.light();
                      setState(() => _cat = c);
                    },
                    backgroundColor: AppColors.surfaceAlt,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12),
                    side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.95),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final a = items[i];
                return GestureDetector(
                  onTap: () {
                    Haptics.light();
                    showGlassDialog(context: context, builder: (ctx) => AlertDialog(
                      title: Row(children: [Text(a.emoji, style: const TextStyle(fontSize: 26)), const SizedBox(width: 10), Expanded(child: Text(a.name))]),
                      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.desc, style: AppTextStyles.bodyMuted),
                        const SizedBox(height: 10),
                        Text(a.unlocked ? '✅ Unlocked · ${a.progressLabel}' : '🔒 ${a.progressLabel}', style: AppTextStyles.caption.copyWith(color: a.unlocked ? AppColors.success : AppColors.textMuted)),
                      ]),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: a.unlocked ? AppGradients.forSeed(a.name) : null,
                      color: a.unlocked ? null : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: a.unlocked ? Colors.transparent : AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Opacity(opacity: a.unlocked ? 1 : 0.35, child: Text(a.emoji, style: const TextStyle(fontSize: 40))),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.name, style: AppTextStyles.label.copyWith(color: a.unlocked ? Colors.white : AppColors.textSecondary)),
                            const SizedBox(height: 4),
                            if (a.unlocked)
                              Text(a.progressLabel, style: AppTextStyles.caption.copyWith(color: Colors.white70))
                            else ...[
                              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: a.progress, minHeight: 5, backgroundColor: AppColors.background, valueColor: const AlwaysStoppedAnimation(AppColors.primary))),
                              const SizedBox(height: 3),
                              Text(a.progressLabel, style: AppTextStyles.captionMuted),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
