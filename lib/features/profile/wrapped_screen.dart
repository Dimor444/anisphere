import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../data/sample_data.dart';

class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key});
  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _WrappedScreenState extends State<WrappedScreen> {
  final _pc = PageController();
  int _page = 0;

  final _slides = const [
    _Slide('🎌', 'Your 2025 Wrapped', 'Let\'s relive your year in anime', AppGradients.brandTri),
    _Slide('📺', '127', 'anime watched this year', AppGradients.brand),
    _Slide('⏱️', 'just over 18 days', 'spent watching anime', AppGradients.purpleCyan),
    _Slide('🏆', 'Frieren', 'was your #1 anime of the year', AppGradients.gold),
    _Slide('🎭', 'Drama & Dark Fantasy', 'were your top genres', AppGradients.gem),
    _Slide('🔥', '42-day', 'longest streak — top 8% of fans', AppGradients.brand),
    _Slide('💜', 'Otaku Elite', 'You leveled up twice this year!', AppGradients.brandTri),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx > w / 2 && !last) {
            _pc.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
          } else if (d.globalPosition.dx <= w / 2 && _page > 0) {
            _pc.previousPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
          }
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pc,
              onPageChanged: (i) {
                Haptics.light();
                setState(() => _page = i);
              },
              itemCount: _slides.length,
              itemBuilder: (_, i) => i == _slides.length - 1 ? _finalSlide() : _slide(_slides[i]),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: List.generate(_slides.length, (i) {
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i <= _page ? Colors.white : Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 8,
              child: IconButton(icon: const Icon(LucideIcons.x, color: Colors.white), onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slide(_Slide s) {
    return Container(
      decoration: BoxDecoration(gradient: s.gradient),
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.emoji, style: const TextStyle(fontSize: 90)).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 20),
          Text(s.big, style: AppTextStyles.display.copyWith(fontSize: 46, color: Colors.white, height: 1.05))
              .animate().fadeIn(delay: 200.ms).slideX(begin: -0.2, end: 0),
          const SizedBox(height: 10),
          Text(s.sub, style: AppTextStyles.heading.copyWith(color: Colors.white70, fontWeight: FontWeight.w500))
              .animate().fadeIn(delay: 400.ms),
        ],
      ),
    );
  }

  Widget _finalSlide() {
    const u = SampleData.mainUser;
    return Container(
      decoration: const BoxDecoration(gradient: AppGradients.brandTri),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('2025 WRAPPED', style: AppTextStyles.caption.copyWith(color: Colors.white70, letterSpacing: 3)),
                  const SizedBox(height: 14),
                  UserAvatar.fromUser(u, radius: 34),
                  const SizedBox(height: 10),
                  Text(u.username, style: AppTextStyles.heading.copyWith(color: Colors.white)),
                  const SizedBox(height: 18),
                  _row('Anime watched', '127'),
                  _row('Hours', '438'),
                  _row('Top anime', 'Frieren'),
                  _row('Top genre', 'Drama'),
                  _row('Level', 'Otaku Elite 👑'),
                ],
              ),
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            GradientButton(
              label: 'Share My Wrapped',
              icon: LucideIcons.share2,
              gradient: const LinearGradient(colors: [Colors.white, Color(0xFFE5E7EB)]),
              onPressed: () {
                Haptics.medium();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to share 🎉'), duration: Duration(seconds: 1)));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 30),
            Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ],
        ),
      );
}

class _Slide {
  final String emoji;
  final String big;
  final String sub;
  final Gradient gradient;
  const _Slide(this.emoji, this.big, this.sub, this.gradient);
}
