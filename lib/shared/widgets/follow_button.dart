import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../services/follow_service.dart';
import '../providers/language_provider.dart';

/// Follow/unfollow toggle for [userId], self-contained: live state from
/// Firestore, optimistic flip on tap, revert + retry snackbar on failure.
/// Busy-guarded so a double-tap can't fire two writes. Renders nothing for
/// the signed-in user's own id.
///
/// Styling: "Follow" = outline, "Following" = gradient fill.
class FollowButton extends ConsumerStatefulWidget {
  final String userId;

  /// Tighter padding for list rows.
  final bool compact;
  const FollowButton({super.key, required this.userId, this.compact = false});

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _busy = false;

  /// Set during an in-flight toggle so the UI flips immediately and ignores
  /// the (stale) stream value until Firestore confirms.
  bool? _optimistic;

  /// Held in state — a stream per build() would re-subscribe on every
  /// rebuild and reopen the not-yet-emitted gap each time.
  late Stream<bool> _stream;

  @override
  void initState() {
    super.initState();
    _stream = FollowService.instance.watchIsFollowing(widget.userId);
  }

  @override
  void didUpdateWidget(FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _optimistic = null;
      _stream = FollowService.instance.watchIsFollowing(widget.userId);
    }
  }

  Future<void> _toggle(bool currentlyFollowing) async {
    if (_busy) return;
    Haptics.light();
    setState(() {
      _busy = true;
      _optimistic = !currentlyFollowing;
    });
    try {
      if (currentlyFollowing) {
        await FollowService.instance.unfollowUser(widget.userId);
      } else {
        await FollowService.instance.followUser(widget.userId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _optimistic = currentlyFollowing);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.tr('actionFailed')),
        action: SnackBarAction(label: ref.tr('retry'), onPressed: () => _toggle(currentlyFollowing)),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId == (AuthService.instance.uid ?? '')) return const SizedBox.shrink();

    return StreamBuilder<bool>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError && _optimistic == null) {
          // Watch broke (offline, permissions): tappable retry, re-subscribes.
          return GestureDetector(
            onTap: () => setState(
                () => _stream = FollowService.instance.watchIsFollowing(widget.userId)),
            child: _shell(following: false, child: _spinnerOrLabel(ref.tr('retry'), spinner: false)),
          );
        }
        // Before the first snapshot the button reads "Follow" and stays
        // tappable — followUser/unfollowUser are idempotent, so a tap during
        // the gap is safe.
        final following = _optimistic ?? snap.data ?? false;
        // Firestore confirmed the optimistic state — hand control back.
        if (_optimistic != null && snap.data == _optimistic && !_busy) _optimistic = null;

        return GestureDetector(
          onTap: _busy ? null : () => _toggle(following),
          child: _shell(
            following: following,
            child: _spinnerOrLabel(
              following ? ref.tr('following') : ref.tr('follow'),
              spinner: _busy,
              onGradient: following,
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required bool following, required Widget child}) {
    final pad = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    return Container(
      padding: pad,
      decoration: BoxDecoration(
        gradient: following ? AppGradients.brand : null,
        borderRadius: BorderRadius.circular(20),
        border: following ? null : Border.all(color: AppColors.primaryLight, width: 1.5),
      ),
      child: child,
    );
  }

  Widget _spinnerOrLabel(String label, {required bool spinner, bool onGradient = false}) {
    final color = onGradient ? Colors.white : AppColors.primaryLight;
    if (spinner) {
      return SizedBox(
        width: 44,
        height: 16,
        child: Center(
          child: SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
        ),
      );
    }
    return Text(label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: widget.compact ? 12 : 12.5));
  }
}
