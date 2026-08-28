import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';

class FmRadioScreen extends StatefulWidget {
  const FmRadioScreen({super.key});
  @override
  State<FmRadioScreen> createState() => _FmRadioScreenState();
}

class _FmRadioScreenState extends State<FmRadioScreen> with TickerProviderStateMixin {
  late final AnimationController _vinyl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  bool _playing = true;
  int _channel = 0;
  int _track = 0;

  final _channels = ['Lo-Fi Anime', 'Openings', 'Epic OST', 'City Pop', 'Vocaloid'];
  final _queue = [
    ('Frieren OST — "Journey"', 'Evan Call'),
    ('Unravel', 'TK from Ling tosite sigure'),
    ('Gurenge', 'LiSA'),
    ('Idol', 'YOASOBI'),
    ('Silhouette', 'KANA-BOON'),
  ];

  @override
  void dispose() {
    _vinyl.dispose();
    _wave.dispose();
    super.dispose();
  }

  void _toggle() {
    Haptics.medium();
    setState(() => _playing = !_playing);
    if (_playing) {
      _vinyl.repeat();
      _wave.repeat();
    } else {
      _vinyl.stop();
      _wave.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🎵 AniSphere FM'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 40),
              Center(
                child: RotationTransition(
                  turns: _vinyl,
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [Color(0xFF1C1F35), Colors.black], radius: 0.9),
                      border: Border.all(color: AppColors.border, width: 2),
                    ),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Text('🎧', style: TextStyle(fontSize: 34)),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(_queue[_track].$1, textAlign: TextAlign.center, style: AppTextStyles.heading),
              Text(_queue[_track].$2, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
              const SizedBox(height: 20),
              SizedBox(height: 50, child: AnimatedBuilder(animation: _wave, builder: (_, __) => CustomPaint(size: const Size(double.infinity, 50), painter: _RadioWave(_wave.value, _playing)))),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(iconSize: 30, icon: const Icon(LucideIcons.skipBack), onPressed: () => setState(() => _track = (_track - 1) % _queue.length)),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: _toggle,
                    child: Container(width: 64, height: 64, decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle), child: Icon(_playing ? LucideIcons.pause : LucideIcons.play, color: Colors.white, size: 28)),
                  ),
                  const SizedBox(width: 16),
                  IconButton(iconSize: 30, icon: const Icon(LucideIcons.skipForward), onPressed: () => setState(() => _track = (_track + 1) % _queue.length)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: List.generate(_channels.length, (i) {
                    final sel = i == _channel;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_channels[i]),
                        selected: sel,
                        onSelected: (_) {
                          Haptics.light();
                          setState(() => _channel = i);
                        },
                        backgroundColor: AppColors.surfaceAlt,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(color: sel ? Colors.white : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                        side: BorderSide(color: sel ? AppColors.primary : AppColors.border),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Up next', style: AppTextStyles.subheading),
              const SizedBox(height: 10),
              ..._queue.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: e.key == _track ? AppColors.primary : AppColors.border)),
                    child: Row(children: [
                      Icon(e.key == _track ? LucideIcons.volume2 : LucideIcons.music, size: 16, color: e.key == _track ? AppColors.primaryLight : AppColors.textMuted),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e.value.$1, style: AppTextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis), Text(e.value.$2, style: AppTextStyles.captionMuted)])),
                    ]),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioWave extends CustomPainter {
  final double t;
  final bool playing;
  _RadioWave(this.t, this.playing);
  @override
  void paint(Canvas canvas, Size size) {
    const bars = 40;
    final w = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final base = playing ? math.sin((i / 4) + t * 2 * math.pi).abs() : 0.15;
      final h = (base * 0.85 + 0.15) * size.height;
      final paint = Paint()..color = Color.lerp(AppColors.primary, AppColors.accent, i / bars)!;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(i * w + w * 0.25, (size.height - h) / 2, w * 0.5, h), const Radius.circular(2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadioWave old) => old.t != t || old.playing != playing;
}
