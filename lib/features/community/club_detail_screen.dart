import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/models/post.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/post_card.dart';
import '../../shared/widgets/user_avatar.dart';

class ClubDetailScreen extends StatelessWidget {
  final String clubName;
  const ClubDetailScreen({super.key, required this.clubName});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              expandedHeight: 170,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(fit: StackFit.expand, children: [
                  DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(clubName))),
                  const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
                  Positioned(left: 16, bottom: 14, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(clubName, style: AppTextStyles.display.copyWith(color: Colors.white)),
                    Text('12.4K members · Public', style: AppTextStyles.caption.copyWith(color: Colors.white70)),
                  ])),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: GradientButton(label: 'Joined ✓', onPressed: () {})),
                      const SizedBox(width: 10),
                      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)), child: const Icon(LucideIcons.bell, size: 18)),
                    ]),
                    const SizedBox(height: 14),
                    const Text('Top members', style: AppTextStyles.subheading),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 70,
                      child: ListView(scrollDirection: Axis.horizontal, children: SampleData.people.map((u) => Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Column(children: [UserAvatar.fromUser(u, radius: 22), const SizedBox(height: 4), SizedBox(width: 60, child: Text(u.username, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppTextStyles.captionMuted))]),
                          )).toList()),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: TabBar(tabs: [Tab(text: 'Feed'), Tab(text: 'Challenges'), Tab(text: 'Chat'), Tab(text: 'Ranks')])),
          ],
          body: TabBarView(children: [
            ListView(padding: const EdgeInsets.only(top: 8, bottom: 30), children: SampleData.posts.take(3).map((p) => PostCard(post: PostData.fromSample(p))).toList()),
            _placeholder('🎯', 'Club challenges', 'Weekly True Fan club battles'),
            _placeholder('💬', 'Club chat', '3,201 members online'),
            _ranks(),
          ]),
        ),
      ),
    );
  }

  Widget _placeholder(String emoji, String title, String sub) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 10),
          Text(title, style: AppTextStyles.heading),
          Text(sub, style: AppTextStyles.bodyMuted),
        ]),
      );

  Widget _ranks() => ListView(
        padding: const EdgeInsets.all(14),
        children: SampleData.leagueLeaders.map((l) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${l.rank}', style: AppTextStyles.numbersLg())),
                UserAvatar.fromUser(l.user, radius: 16),
                const SizedBox(width: 10),
                Expanded(child: Text(l.user.username, style: AppTextStyles.label)),
                Text('${l.lp} pts', style: AppTextStyles.numbers.copyWith(color: AppColors.aniGold)),
              ]),
            )).toList(),
      );
}
