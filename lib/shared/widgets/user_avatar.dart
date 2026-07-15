import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../data/models/user_model.dart';

/// Avatar with a level-based "aura" glow. Higher tiers animate.
/// Verification is shown by the name-row badge, not on the avatar.
class UserAvatar extends StatefulWidget {
  final String name;
  final UserLevel level;

  /// Profile picture URL — shown over the gradient when set; falls back to
  /// initials if empty or the image fails to load.
  final String? imageUrl;

  /// Overrides the initials derived from [name].
  final String? initials;

  /// Shows a green presence dot at the bottom-right when true.
  final bool isOnline;
  final double radius;
  final VoidCallback? onTap;

  const UserAvatar({
    super.key,
    required this.name,
    this.level = UserLevel.animeFan,
    this.imageUrl,
    this.initials,
    this.isOnline = false,
    this.radius = 24,
    this.onTap,
  });

  UserAvatar.fromUser(UserModel u, {super.key, this.radius = 24, this.onTap, this.isOnline = false})
      : name = u.username,
        level = u.level,
        imageUrl = null,
        initials = null;

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();

  /// Set when the network image errors — reverts to gradient + initials.
  bool _imageFailed = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _initials {
    final override = widget.initials;
    if (override != null && override.isNotEmpty) return override;
    final n = widget.name.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (n.isEmpty) return '?';
    return n.length >= 2 ? n.substring(0, 2).toUpperCase() : n.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    final pair = AppGradients.pairForSeed(widget.name);
    final url = widget.imageUrl?.trim() ?? '';
    final showImage = url.isNotEmpty && !_imageFailed;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: _aura(_c.value),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: r * 2,
                  height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: pair,
                    ),
                    // Gradient keeps showing while the image loads; the border
                    // paints on top either way.
                    image: showImage
                        ? DecorationImage(
                            image: NetworkImage(url),
                            fit: BoxFit.cover,
                            onError: (_, __) {
                              if (mounted) setState(() => _imageFailed = true);
                            },
                          )
                        : null,
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 2),
                  ),
                  alignment: Alignment.center,
                  child: showImage
                      ? null
                      : Text(
                          _initials,
                          style: TextStyle(
                            fontSize: r * 0.7,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                ),
                // Green presence dot at the bottom-right corner.
                if (widget.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: (r * 0.5).clamp(9.0, 16.0),
                      height: (r * 0.5).clamp(9.0, 16.0),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<BoxShadow> _aura(double t) {
    switch (widget.level.aura) {
      case AuraType.none:
        return const [];
      case AuraType.white:
        return [BoxShadow(color: AppColors.glowWhite.withOpacity(0.45), blurRadius: 12, spreadRadius: 1)];
      case AuraType.blue:
        return [BoxShadow(color: AppColors.glowBlue.withOpacity(0.55), blurRadius: 16, spreadRadius: 1)];
      case AuraType.orange:
        return [BoxShadow(color: AppColors.glowOrange.withOpacity(0.6), blurRadius: 18, spreadRadius: 1)];
      case AuraType.purpleShimmer:
        final pulse = 0.4 + 0.35 * (0.5 + 0.5 * _wave(t));
        return [BoxShadow(color: AppColors.glowPurple.withOpacity(pulse), blurRadius: 20 + 8 * _wave(t), spreadRadius: 2)];
      case AuraType.rainbowGold:
        final hue = (t * 360) % 360;
        final color = HSVColor.fromAHSV(1, hue, 0.7, 1).toColor();
        return [
          BoxShadow(color: color.withOpacity(0.6), blurRadius: 22, spreadRadius: 2),
          BoxShadow(color: AppColors.glowGold.withOpacity(0.4), blurRadius: 12, spreadRadius: 1),
        ];
    }
  }

  double _wave(double t) {
    final x = (t * 2 - 1).abs(); // triangle 0..1..0
    return 1 - x;
  }
}
