import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/theme/brand.dart';
import '../../core/widgets/anisphere_logo.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/language_sheet.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  // Deterministic decorative particle field (position fractions, radius, color index).
  static const _particles = <List<double>>[
    [0.08, 0.12, 3.0, 0], [0.85, 0.08, 2.0, 1], [0.15, 0.75, 4.0, 2],
    [0.90, 0.70, 2.5, 3], [0.50, 0.05, 1.5, 0], [0.05, 0.45, 3.5, 1],
    [0.92, 0.38, 2.0, 2], [0.30, 0.88, 3.0, 3], [0.70, 0.92, 1.5, 0],
    [0.45, 0.16, 2.5, 1], [0.78, 0.55, 2.0, 2], [0.22, 0.55, 3.0, 3],
  ];
  static const _particleColors = [
    AniSphereBrand.blue, AniSphereBrand.indigo,
    AniSphereBrand.violet, AniSphereBrand.magenta,
  ];

  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 2800), () {
      if (mounted) context.go('/onboarding');
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider).code;
    final media = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Deep space-violet ground
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.pageBg)),
          ),

          // Decorative particle dots
          for (final p in _particles)
            Positioned(
              left: media.width * p[0],
              top: media.height * p[1],
              child: _Particle(radius: p[2], color: _particleColors[p[3].toInt()]),
            ),

          // Pulsing radial glow behind the mark
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AniSphereBrand.glowGradient,
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleXY(begin: 0.85, end: 1.15, duration: 2400.ms, curve: Curves.easeInOut),
          ),

          // Logo + wordmark + tagline
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AniSphereLogo(size: 140)
                    .animate()
                    .scale(
                      begin: const Offset(0.6, 0.6),
                      end: const Offset(1, 1),
                      duration: 800.ms,
                      curve: Curves.easeOutBack,
                    )
                    .fadeIn(duration: 600.ms),
                const SizedBox(height: 26),
                ShaderMask(
                  shaderCallback: (r) => AppGradients.brand.createShader(r),
                  child: Text(
                    'AniSphere',
                    style: AppTextStyles.display
                        .copyWith(fontSize: 40, color: Colors.white, letterSpacing: -0.8),
                  ),
                ).animate().fadeIn(delay: 450.ms, duration: 600.ms).slideY(begin: 0.2, end: 0),
                const SizedBox(height: 12),
                Text(
                  ref.tr('tagline'),
                  style: AppTextStyles.bodyMuted.copyWith(letterSpacing: 3.0),
                )
                    .animate()
                    .fadeIn(delay: 900.ms, duration: 700.ms)
                    .slideY(begin: 0.4, end: 0, delay: 900.ms),
              ],
            ),
          ),

          // Brand loading bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 78,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 2300),
                curve: Curves.easeInOut,
                builder: (_, value, __) => Container(
                  width: 130,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppGradients.brand,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 350.ms),
            ),
          ),

          // +14 age chip
          Positioned(
            left: 18,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text('+14',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700)),
            ),
          ),

          // Language selector
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: TextButton.icon(
                onPressed: () => showLanguageSheet(context),
                icon: const Icon(LucideIcons.globe, size: 18, color: AppColors.textSecondary),
                label: Text(
                  languageName(lang),
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
              ).animate().fadeIn(delay: 1400.ms),
            ),
          ),
        ],
      ),
    );
  }
}

class _Particle extends StatelessWidget {
  final double radius;
  final Color color;
  const _Particle({required this.radius, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.4),
        boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)],
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .fadeIn(duration: 1200.ms)
        .then()
        .fade(begin: 1, end: 0.3, duration: 1600.ms, curve: Curves.easeInOut);
  }
}
