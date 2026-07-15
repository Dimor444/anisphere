import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

enum BadgeSize { sm, md, lg }

/// Twitter-style verification seal: a 12-pointed scalloped starburst with a
/// white checkmark, rendered entirely with CustomPaint.
class VerifiedBadge extends StatelessWidget {
  final BadgeSize size;
  final Color color;
  const VerifiedBadge({super.key, this.size = BadgeSize.md, this.color = AppColors.verified});

  double get _px => switch (size) {
        BadgeSize.sm => 14,
        BadgeSize.md => 16,
        BadgeSize.lg => 20,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _px,
      height: _px,
      child: CustomPaint(painter: _SealPainter(color)),
    );
  }
}

class _SealPainter extends CustomPainter {
  final Color color;
  _SealPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.width / 2;
    final inner = outer * 0.82;
    const bumps = 12;
    final path = Path();
    for (var i = 0; i < bumps * 2; i++) {
      final r = i.isEven ? outer : inner;
      final a = (math.pi / bumps) * i - math.pi / 2;
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.fill);

    // checkmark
    final check = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final mark = Path()
      ..moveTo(w * 0.30, w * 0.52)
      ..lineTo(w * 0.44, w * 0.66)
      ..lineTo(w * 0.72, w * 0.36);
    canvas.drawPath(mark, check);
  }

  @override
  bool shouldRepaint(covariant _SealPainter old) => old.color != color;
}
