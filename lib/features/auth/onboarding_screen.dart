import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/theme/brand.dart';
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

  // Each slide's art is drawn in code — flat brand-green shapes, nothing
  // bundled or fetched, so nothing on the first screens belongs to anyone else.
  static const _pages = [
    _OnbData(
      'One World, Every Anime',
      'Follow, post, and react with millions of fans. Your feed, your fandom.',
      AppColors.primaryDark,
      _OrbitArt(),
    ),
    _OnbData(
      'Prove You\'re a True Fan',
      'Compete in quizzes, climb the League, and earn AniGold for what you love.',
      AniSphereBrand.blue,
      _ClimbArt(),
    ),
    _OnbData(
      'Find Your Anime Soulmate',
      'AniMatch connects you with people who share your exact taste.',
      AniSphereBrand.indigo,
      _MatchArt(),
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
  final String title;
  final String sub;
  final Color background;
  final CustomPainter art;
  const _OnbData(this.title, this.sub, this.background, this.art);
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
                color: data.background,
                borderRadius: BorderRadius.circular(28),
              ),
              child: CustomPaint(painter: data.art),
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
}

// ── Slide art ─────────────────────────────────────────────────────────────
// Flat tonal shapes only — the brand was flattened (no glows), so depth comes
// from stacking greens, not from blur. Every measurement is a fraction of the
// card so the art holds its composition on any screen size.

const _mint = AppColors.primaryLight; // #7FD9A8
const _emerald = AniSphereBrand.indigo; // #1DB367
const _bright = AniSphereBrand.magenta; // #34D17F
const _deep = AppColors.primaryDark; // #0A5C3C
const _ink = AniSphereBrand.bgDark; // #04160C

Paint _fill(Color c, [double opacity = 1]) => Paint()..color = c.withOpacity(opacity);
Paint _stroke(Color c, double width, [double opacity = 1]) => Paint()
  ..color = c.withOpacity(opacity)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round;

/// Oversized soft discs bleeding off the edges — the shared backdrop that
/// keeps three different motifs reading as one set.
void _backdrop(Canvas canvas, Size size, Color tone) {
  final s = size.shortestSide;
  canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.08), s * 0.42, _fill(tone, 0.18));
  canvas.drawCircle(Offset(size.width * 1.02, size.height * 0.96), s * 0.55, _fill(tone, 0.14));
}

/// One World: a planet with two tilted orbits and the fans circling it.
class _OrbitArt extends CustomPainter {
  const _OrbitArt();

  @override
  void paint(Canvas canvas, Size size) {
    _backdrop(canvas, size, _emerald);
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.24;

    // Far half of each orbit, then the planet, then the near half — so the
    // rings wrap around the globe instead of lying flat behind it.
    _orbits(canvas, c, r, front: false);

    // The planet: a disc with a lit crescent and a band across it.
    canvas.drawCircle(c, r, _fill(_emerald));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(c.translate(r * 0.35, r * 0.35), r, _fill(_deep, 0.55));
    canvas.drawRect(Rect.fromLTWH(c.dx - r, c.dy - r * 0.12, r * 2, r * 0.24), _fill(_mint, 0.45));
    canvas.restore();

    _orbits(canvas, c, r, front: true);
  }

  void _orbits(Canvas canvas, Offset c, double r, {required bool front}) {
    for (final (tilt, scale) in [(-0.35, 1.9), (0.5, 1.55)]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(tilt);
      final orbit = Rect.fromCenter(center: Offset.zero, width: r * scale * 2, height: r * scale * 0.8);
      // In the orbit's own frame the near half is the lower one.
      canvas.clipRect(Rect.fromLTRB(-orbit.width, front ? 0 : -orbit.height, orbit.width, front ? orbit.height : 0));
      canvas.drawOval(orbit, _stroke(_mint, 2, 0.55));
      // Satellites sit on the orbit's ellipse.
      for (final t in [0.4, 2.3, 4.1]) {
        final p = Offset(math.cos(t) * orbit.width / 2, math.sin(t) * orbit.height / 2);
        if ((p.dy >= 0) != front) continue;
        canvas.drawCircle(p, r * 0.11, _fill(t == 2.3 ? Colors.white : _bright));
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// True Fan: rising bars, the tallest crowned with a star.
class _ClimbArt extends CustomPainter {
  const _ClimbArt();

  @override
  void paint(Canvas canvas, Size size) {
    _backdrop(canvas, size, _mint);
    final w = size.width, h = size.height;
    final barW = w * 0.17, gap = w * 0.05;
    final base = h * 0.8;
    final left = (w - barW * 3 - gap * 2) / 2;
    final heights = [0.26, 0.40, 0.54];
    final colours = [_deep, _emerald, _mint];

    for (var i = 0; i < 3; i++) {
      final x = left + i * (barW + gap);
      final top = base - h * heights[i];
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTRB(x, top, x + barW, base),
            topLeft: const Radius.circular(12), topRight: const Radius.circular(12)),
        _fill(colours[i]),
      );
      // Rank tick on each bar.
      canvas.drawLine(Offset(x + barW * 0.3, top + barW * 0.35), Offset(x + barW * 0.7, top + barW * 0.35),
          _stroke(_ink, 4, 0.35));
    }
    canvas.drawLine(Offset(w * 0.12, base), Offset(w * 0.88, base), _stroke(_ink, 3, 0.3));

    final lastX = left + 2 * (barW + gap) + barW / 2;
    _star(canvas, Offset(lastX, base - h * heights[2] - barW * 0.75), barW * 0.5);
    // The climb itself: a dotted arc up to the star.
    for (var t = 0.0; t <= 1.0; t += 0.1) {
      final p = Offset(left + barW / 2 + (lastX - left - barW / 2) * t,
          base - h * heights[0] - h * 0.1 - math.sin(t * math.pi * 0.5) * h * 0.26);
      canvas.drawCircle(p, 3, _fill(Colors.white, 0.35 + t * 0.5));
    }
  }

  void _star(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), _fill(Colors.white));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Soulmate: two circles of taste, their overlap lit — the shared part is
/// what AniMatch finds.
class _MatchArt extends CustomPainter {
  const _MatchArt();

  @override
  void paint(Canvas canvas, Size size) {
    _backdrop(canvas, size, _deep);
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.27;
    final a = c.translate(-r * 0.55, 0), b = c.translate(r * 0.55, 0);
    final ca = Path()..addOval(Rect.fromCircle(center: a, radius: r));
    final cb = Path()..addOval(Rect.fromCircle(center: b, radius: r));

    canvas.drawPath(ca, _fill(_deep));
    canvas.drawPath(cb, _fill(_mint));
    canvas.drawPath(Path.combine(PathOperation.intersect, ca, cb), _fill(Colors.white));

    // Taste dots scattered in each circle; two land in the shared lens.
    final rnd = math.Random(7);
    for (final (centre, colour) in [(a, _bright), (b, _deep)]) {
      for (var i = 0; i < 6; i++) {
        final ang = rnd.nextDouble() * math.pi * 2, d = r * (0.35 + rnd.nextDouble() * 0.45);
        final p = centre + Offset(math.cos(ang) * d, math.sin(ang) * d);
        if (Path.combine(PathOperation.intersect, ca, cb).contains(p)) continue;
        canvas.drawCircle(p, r * 0.05, _fill(colour, 0.8));
      }
    }
    canvas.drawCircle(c.translate(0, -r * 0.22), r * 0.07, _fill(_emerald));
    canvas.drawCircle(c.translate(0, r * 0.22), r * 0.07, _fill(_emerald));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
