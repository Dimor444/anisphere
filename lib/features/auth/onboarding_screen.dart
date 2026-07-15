import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  // Real anime cast per slide — AniList character artwork.
  static const _pages = [
    _OnbData(
      [
        'https://s4.anilist.co/file/anilistcdn/character/large/b40-MNypXsxSRb1R.png', // Luffy
        'https://s4.anilist.co/file/anilistcdn/character/large/b17-phjcWCkRuIhu.png', // Naruto
        'https://s4.anilist.co/file/anilistcdn/character/large/246-wsRRr6z1kii8.png', // Goku
        'https://s4.anilist.co/file/anilistcdn/character/large/b126071-BTNEc1nRIv68.png', // Tanjiro
      ],
      'One World, Every Anime',
      'Follow, post, and react with millions of fans. Your feed, your fandom.',
      AppGradients.brand,
      imagePath: 'assets/images/one_world_every_anime.png',
    ),
    _OnbData(
      [
        'https://s4.anilist.co/file/anilistcdn/character/large/b127691-9zqh1xpIubn7.png', // Gojo
        'https://s4.anilist.co/file/anilistcdn/character/large/b45627-CR68RyZmddGG.png', // Levi
        'https://s4.anilist.co/file/anilistcdn/character/large/b130102-FO1VHNnEnLlB.png', // Denji
        'https://s4.anilist.co/file/anilistcdn/character/large/b27-Z5O02kQUydpT.jpg', // Killua
      ],
      'Prove You\'re a True Fan',
      'Compete in quizzes, climb the League, and earn AniGold for what you love.',
      AppGradients.purpleCyan,
      imagePath: 'assets/images/fan_challenges.png',
    ),
    _OnbData(
      [
        'https://s4.anilist.co/file/anilistcdn/character/large/b138100-4Li0tWRCa5bQ.png', // Anya
        'https://s4.anilist.co/file/anilistcdn/character/large/b176754-PCnpqIOkjhFk.png', // Frieren
        'https://s4.anilist.co/file/anilistcdn/character/large/b129131-FZrQ7lSlxmEr.png', // Zenitsu
        'https://s4.anilist.co/file/anilistcdn/character/large/b137079-6yLEUYR3bmpr.png', // Power
      ],
      'Find Your Anime Soulmate',
      'AniMatch connects you with people who share your exact taste.',
      AppGradients.gem,
      imagePath: 'assets/images/soulmate.png',
    ),
  ];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        // Column layout: scrollable page area on top, controls in normal flow
        // below — nothing is stacked over the content, so nothing can overlap.
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _pc,
                    onPageChanged: (i) {
                      Haptics.light();
                      setState(() => _page = i);
                    },
                    itemCount: _pages.length,
                    itemBuilder: (_, i) => _OnbPage(data: _pages[i]),
                  ),
                  // skip
                  if (!last)
                    Positioned(
                      top: 8,
                      right: 12,
                      child: TextButton(
                        onPressed: () => _pc.animateToPage(_pages.length - 1,
                            duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
                        child: Text(ref.tr('skip'),
                            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                      ),
                    ),
                ],
              ),
            ),
            // bottom controls
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: active ? AppGradients.brand : null,
                          color: active ? null : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  if (last) ...[
                    GradientButton(
                      label: ref.tr('createAccount'),
                      onPressed: () => context.go('/signup'),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => context.go('/signin'),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(ref.tr('signIn'),
                            style: AppTextStyles.subheading.copyWith(color: AppColors.textSecondary)),
                      ),
                    ),
                  ] else
                    GradientButton(
                      label: ref.tr('next'),
                      onPressed: () => _pc.nextPage(
                          duration: const Duration(milliseconds: 350), curve: Curves.easeOut),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnbData {
  final List<String> cast; // AniList character image URLs
  final String title;
  final String sub;
  final Gradient gradient;
  final String? imagePath; // optional full-bleed slide image (overrides [cast])
  const _OnbData(this.cast, this.title, this.sub, this.gradient, {this.imagePath});
}

class _OnbPage extends StatelessWidget {
  final _OnbData data;
  const _OnbPage({required this.data});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: data.gradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: data.gradient.colors.last.withOpacity(0.4), blurRadius: 40)],
              ),
              alignment: Alignment.center,
              child: data.imagePath != null
                  ? Image.asset(
                      data.imagePath!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      // Until the file is added, fall back to the cast lineup.
                      errorBuilder: (_, __, ___) => _cast(),
                    )
                  : _cast(),
            ),
          ),
          const SizedBox(height: 30),
          Text(data.title, style: AppTextStyles.display, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(data.sub, style: AppTextStyles.bodyMuted, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  /// Default slide illustration: overlapping real-anime portrait lineup.
  Widget _cast() {
    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 300,
          height: 360,
          child: Stack(
            children: [
              // Decorative sparkles fill the card's negative space.
              const _Sparkle(left: 28, top: 44, size: 24, opacity: 0.30),
              const _Sparkle(left: 244, top: 30, size: 30, opacity: 0.26),
              const _Sparkle(left: 150, top: 22, size: 18, opacity: 0.22),
              const _Sparkle(left: 278, top: 150, size: 20, opacity: 0.24),
              const _Sparkle(left: 12, top: 252, size: 26, opacity: 0.28),
              _CharPortrait(url: data.cast[0], left: 2, top: 130, width: 110, height: 230),
              _CharPortrait(url: data.cast[1], left: 64, top: 74, width: 128, height: 286),
              _CharPortrait(url: data.cast[2], left: 150, top: 100, width: 122, height: 260),
              _CharPortrait(url: data.cast[3], left: 226, top: 152, width: 72, height: 208),
            ],
          ),
        ),
      ),
    );
  }
}

/// A real anime character portrait (AniList artwork) in a rounded frame.
/// Placed with [Positioned] inside a [Stack]; overlap comes from positioning.
class _CharPortrait extends StatelessWidget {
  final String url;
  final double left, top, width, height;
  const _CharPortrait({
    required this.url,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.85), width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            placeholder: (_, __) => const ColoredBox(color: Colors.white24),
            errorWidget: (_, __, ___) => const ColoredBox(color: Colors.white24),
          ),
        ),
      ),
    );
  }
}

/// A small decorative sparkle used to fill the illustration's negative space.
class _Sparkle extends StatelessWidget {
  final double left;
  final double top;
  final double size;
  final double opacity;
  const _Sparkle({
    required this.left,
    required this.top,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Icon(Icons.auto_awesome, size: size, color: Colors.white.withOpacity(opacity)),
    );
  }
}
