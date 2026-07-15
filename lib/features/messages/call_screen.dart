import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/user_model.dart';
import '../../shared/widgets/user_avatar.dart';

/// A simulated voice / video call screen. There's no real telephony backend,
/// so this rings for a beat, "connects", runs a live duration timer, and offers
/// working mute / speaker / camera / end-call controls.
///
/// When [autoConnect] is true (an *accepted incoming* call) it skips the ring
/// and connects immediately.
///
/// Pops with the final elapsed call duration **in seconds** (an `int`) so the
/// caller can log a "Call ended · mm:ss" message. Ending before the call
/// connects pops with `0`.
class CallScreen extends StatefulWidget {
  final UserModel user;
  final bool video;
  final bool autoConnect;
  const CallScreen({super.key, required this.user, this.video = false, this.autoConnect = false});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _connected = false;
  int _seconds = 0;
  Timer? _ring;
  Timer? _tick;
  bool _ended = false; // guards against ending twice (button + swipe-back)

  bool _muted = false;
  bool _speaker = true;
  bool _cameraOn = true;

  @override
  void initState() {
    super.initState();
    Haptics.medium();
    if (widget.autoConnect) {
      _connected = true;
      _startTick();
    } else {
      // Ring for ~2.2s, then "connect" and start the duration clock.
      _ring = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted) return; // (#2) never setState on a disposed widget
        Haptics.heavy();
        setState(() => _connected = true);
        _startTick();
      });
    }
  }

  void _startTick() {
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _ring?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  /// Single source of truth for ending a call: cancel both timers (including
  /// the still-pending connect timer, #1) and pop back with the duration.
  void _end() {
    if (_ended) return;
    _ended = true;
    _ring?.cancel();
    _tick?.cancel();
    Haptics.medium();
    Navigator.of(context).pop(_seconds);
  }

  String get _status {
    if (!_connected) return widget.video ? 'Video calling…' : 'Calling…';
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.user.displayName ?? widget.user.username;
    final showFeed = widget.video && _cameraOn;
    // (#3) canPop:false routes the iOS swipe-back through _end() so it gets the
    // same cleanup (haptic + timer cancel + return duration) as the End button.
    return PopScope<int>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _end();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Video "feed" stand-in (a gradient) + legibility overlay.
            if (showFeed)
              DecoratedBox(decoration: BoxDecoration(gradient: AppGradients.forSeed(widget.user.username))),
            if (showFeed)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent, Colors.black87],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),

            // Caller identity + status.
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  if (!showFeed) ...[
                    UserAvatar.fromUser(widget.user, radius: 58),
                    const SizedBox(height: 22),
                  ],
                  Text(name, style: AppTextStyles.heading.copyWith(color: Colors.white, fontSize: 26)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_connected)
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                        ),
                      Text(_status, style: AppTextStyles.subheading.copyWith(color: Colors.white70, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (!_connected) ...[
                    const SizedBox(height: 18),
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white54)),
                  ],
                ],
              ),
            ),

            // Self-view PiP (video only).
            if (widget.video)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: Container(
                  width: 96,
                  height: 132,
                  decoration: BoxDecoration(
                    gradient: _cameraOn ? AppGradients.brand : null,
                    color: _cameraOn ? null : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_cameraOn ? LucideIcons.user : LucideIcons.videoOff, color: Colors.white70, size: 28),
                ),
              ),

            // Controls.
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ctrl(
                            icon: _muted ? LucideIcons.micOff : LucideIcons.mic,
                            label: _muted ? 'Unmute' : 'Mute',
                            active: _muted,
                            onTap: () {
                              Haptics.light();
                              setState(() => _muted = !_muted);
                            },
                          ),
                          const SizedBox(width: 22),
                          if (widget.video)
                            _ctrl(
                              icon: _cameraOn ? LucideIcons.video : LucideIcons.videoOff,
                              label: _cameraOn ? 'Camera' : 'Camera off',
                              active: !_cameraOn,
                              onTap: () {
                                Haptics.light();
                                setState(() => _cameraOn = !_cameraOn);
                              },
                            )
                          else
                            _ctrl(
                              icon: _speaker ? LucideIcons.volume2 : LucideIcons.volumeX,
                              label: 'Speaker',
                              active: _speaker,
                              onTap: () {
                                Haptics.light();
                                setState(() => _speaker = !_speaker);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      GestureDetector(
                        onTap: _end,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                          child: const Icon(LucideIcons.phoneOff, color: Colors.white, size: 30),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('End', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ctrl({required IconData icon, required String label, required bool active, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(shape: BoxShape.circle, color: active ? Colors.white : Colors.white24),
            child: Icon(icon, color: active ? Colors.black : Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
