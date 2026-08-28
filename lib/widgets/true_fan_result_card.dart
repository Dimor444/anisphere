import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_gradients.dart';
import '../core/constants/app_text_styles.dart';
import '../core/utils/formatters.dart';
import '../data/models/user_model.dart';
import '../shared/widgets/user_avatar.dart';

/// A polished, share-ready "True Fan" trophy card. Rendered inside a
/// [RepaintBoundary] so it can be captured to an image and shared.
///
/// Shows the AniSphere watermark, the anime cover + name, the player's avatar,
/// a circular score ring, time taken and a (placeholder) world rank.
class TrueFanResultCard extends StatelessWidget {
  final String animeName;
  final String? coverUrl;
  final int score; // 0..10
  final double timeSeconds;
  final int rank;
  final UserModel user;

  const TrueFanResultCard({
    super.key,
    required this.animeName,
    required this.coverUrl,
    required this.score,
    required this.timeSeconds,
    required this.rank,
    required this.user,
  });

  String get _tier => score >= 9
      ? 'LEGENDARY FAN'
      : score >= 7
          ? 'TRUE FAN'
          : score >= 5
              ? 'RISING FAN'
              : 'ROOKIE';

  @override
  Widget build(BuildContext context) {
    // Gradient "frame" → inner dark card.
    return Container(
      decoration: BoxDecoration(
        gradient: AppGradients.purpleCyan,
        borderRadius: BorderRadius.circular(26),
        // Neutral lift — deliberately black, not brand-tinted, so the card
        // separates from the background without a coloured haze.
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.surfaceAlt, AppColors.background],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const SizedBox(height: 14),
            _cover(),
            const SizedBox(height: 16),
            _ScoreRing(score: score),
            const SizedBox(height: 8),
            _tierBadge(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _statTile(Icons.timer_rounded, '${timeSeconds.toStringAsFixed(1)}s', 'TIME', AppColors.accent)),
                const SizedBox(width: 12),
                Expanded(child: _statTile(Icons.public_rounded, '#${Fmt.thousands(rank)}', 'WORLD RANK', AppColors.primaryLight)),
              ],
            ),
            const SizedBox(height: 16),
            _userRow(),
            const SizedBox(height: 12),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ── AniSphere watermark + challenge label ──────────────────
  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            ShaderMask(
              shaderCallback: (r) => AppGradients.brand.createShader(r),
              child: const Text(
                'AniSphere',
                style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.3),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.auto_awesome, size: 15, color: AppColors.aniGold),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.6)),
          ),
          child: const Text(
            'TRUE FAN',
            style: TextStyle(color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          ),
        ),
      ],
    );
  }

  // ── Cover banner + anime name ──────────────────────────────
  Widget _cover() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 168,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl != null && coverUrl!.isNotEmpty)
              Image.network(
                coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _coverPlaceholder(),
                loadingBuilder: (_, child, progress) => progress == null ? child : _coverPlaceholder(),
              )
            else
              _coverPlaceholder(),
            // legibility scrim
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54, Colors.black87],
                  stops: [0.35, 0.7, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PROVED THEIR FANDOM FOR',
                      style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
                  const SizedBox(height: 2),
                  Text(
                    animeName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 1.05),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder() {
    final letter = animeName.trim().isNotEmpty ? animeName.trim()[0].toUpperCase() : '?';
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppGradients.forSeed(animeName)),
      child: Center(
        child: Text(letter, style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _tierBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '🏆  $_tier',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1),
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
        ],
      ),
    );
  }

  Widget _userRow() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          UserAvatar.fromUser(user, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@${user.username}', style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700)),
                Text(user.level.title, style: AppTextStyles.captionMuted),
              ],
            ),
          ),
          if (user.country.isNotEmpty) Text(user.country, style: const TextStyle(fontSize: 22)),
        ],
      ),
    );
  }

  Widget _footer() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.auto_awesome, size: 11, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Text('Play True Fan on AniSphere  ·  #AniSphere',
            style: AppTextStyles.captionMuted.copyWith(fontSize: 10, letterSpacing: 0.3)),
      ],
    );
  }
}

/// Circular score ring with a purple→cyan gradient arc and "X / 10" inside.
class _ScoreRing extends StatelessWidget {
  final int score;
  const _ScoreRing({required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      height: 132,
      child: CustomPaint(
        painter: _RingPainter(progress: (score / 10).clamp(0.0, 1.0)),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$score',
                      style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, height: 1),
                    ),
                    const TextSpan(
                      text: ' / 10',
                      style: TextStyle(color: Colors.white60, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Text('CORRECT',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.08);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [AppColors.primary, AppColors.accent, AppColors.secondary, AppColors.primary],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
