import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/models/user.dart';
import '../../services/currency_service.dart';
import 'verified_badge.dart';

/// One clock for every shimmering name on screen.
///
/// The naive shape is an AnimationController per name, which in a fifty-row
/// feed is fifty tickers competing to schedule the same frames. This is one
/// Ticker driving one ValueNotifier; each name listens and repaints. Fifty
/// names cost one ticker and fifty listeners.
///
/// It is reference counted by MOUNTED SHIMMERING WIDGETS, not by "is anything
/// equipped" — the count is the only thing that actually knows whether a
/// shimmer is on screen right now. Scrolling the last shimmering author out
/// of the list disposes that widget, drops the count to zero and stops the
/// ticker; scrolling one back in starts it again. Nobody equipping the effect
/// means the ticker never starts at all, which is the common case.
class _ShimmerClock {
  _ShimmerClock._();
  static final _ShimmerClock instance = _ShimmerClock._();

  /// One full sweep of the gradient, in milliseconds.
  static const int _periodMs = 2600;

  /// 0..1, where the gradient currently sits. Repaints ride on this.
  final ValueNotifier<double> phase = ValueNotifier<double>(0);

  Ticker? _ticker;
  int _mounted = 0;

  void acquire() {
    _mounted++;
    // A bare Ticker rather than an AnimationController: there is no vsync to
    // borrow outside the tree, and it only fires while the engine is
    // producing frames — so a backgrounded app stops it without extra work.
    _ticker ??= Ticker(_tick)..start();
  }

  void release() {
    _mounted--;
    if (_mounted > 0) return;
    // Clamped rather than asserted: a release without an acquire would be a
    // bug, but leaving a ticker running forever is a worse way to find out.
    _mounted = 0;
    _ticker?.dispose();
    _ticker = null;
    // Reset so the next shimmer starts from a known phase instead of
    // resuming wherever the last one stopped.
    phase.value = 0;
  }

  void _tick(Duration elapsed) {
    phase.value = (elapsed.inMilliseconds % _periodMs) / _periodMs;
  }
}

/// The repeated cluster: a name that ellipsises, and an optional badge that
/// never shrinks.
///
/// Private because it is an implementation detail shared by the two public
/// widgets, not a third thing to reach for. [UserNameText] and
/// [UserHandleText] differ in what they render and whether an effect applies;
/// the row itself was identical in six places and is now written once.
class _NameRow extends StatelessWidget {
  final Widget text;
  final bool verified;
  final BadgeSize badgeSize;
  final double gap;
  const _NameRow({
    required this.text,
    required this.verified,
    required this.badgeSize,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    if (!verified) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        SizedBox(width: gap),
        VerifiedBadge(size: badgeSize),
      ],
    );
  }
}

/// A person's display name, with their verified badge and name effect.
///
/// Takes a [TextStyle] rather than choosing one: the five styles across the
/// app (subheading, caption+w700, label, display@22, captionMuted) are the
/// callers' business — a header name and a comment byline are not the same
/// typography, and a widget that decided for them would be wrong five ways.
///
/// [user] may be null while the document loads. That is the ONLY source of
/// the effect, so a name renders plain until the doc arrives and then
/// shimmers. Nothing reflows when it does: the effect is a ShaderMask around
/// the same Text with the same style, so it changes how the glyphs are
/// painted and not how they are laid out.
class UserNameText extends StatefulWidget {
  /// The resolved profile, or null while it loads. Null renders [fallback]
  /// plain — no badge, no effect.
  final UserData? user;

  /// Shown when [user] has not resolved. Usually the value denormalized on
  /// the post/comment/entry.
  final String fallback;

  final TextStyle style;
  final BadgeSize badgeSize;
  final double badgeGap;
  final int maxLines;

  /// Rendered instead of the resolved name — for the leaderboard's
  /// "Name (you)". The effect and badge still apply.
  final String Function(String name)? decorate;

  const UserNameText({
    super.key,
    required this.user,
    required this.style,
    this.fallback = '',
    this.badgeSize = BadgeSize.sm,
    this.badgeGap = 4,
    this.maxLines = 1,
    this.decorate,
  });

  @override
  State<UserNameText> createState() => _UserNameTextState();
}

class _UserNameTextState extends State<UserNameText> {
  bool _shimmering = false;

  bool get _wantsShimmer =>
      widget.user?.equippedIn(CosmeticSlot.nameEffect) == 'rainbow_shimmer';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(UserNameText old) {
    super.didUpdateWidget(old);
    // The doc arriving, or the user equipping/unequipping, flips this without
    // the widget being remounted.
    _sync();
  }

  void _sync() {
    final want = _wantsShimmer;
    if (want == _shimmering) return;
    want ? _ShimmerClock.instance.acquire() : _ShimmerClock.instance.release();
    _shimmering = want;
  }

  @override
  void dispose() {
    if (_shimmering) _ShimmerClock.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.user?.nameToShow ?? widget.fallback;
    final shown = widget.decorate?.call(resolved) ?? resolved;

    Widget text = Text(
      shown,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
    );

    if (_shimmering) text = _Shimmer(child: text);

    return _NameRow(
      text: text,
      verified: widget.user?.isVerified ?? false,
      badgeSize: widget.badgeSize,
      gap: widget.badgeGap,
    );
  }
}

/// A person's @handle. Muted secondary identity — never carries the name
/// effect.
///
/// Deliberately a separate widget rather than a flag on [UserNameText]. The
/// two differ in what they read, how they are styled by convention, and
/// whether a cosmetic applies; one widget with a `showHandle` bool would need
/// a second bool for the effect and would read as a mode switch rather than
/// two things.
///
/// The handle stays plain because it sits under the name in six of its nine
/// sites at captionMuted — shimmering it would fight the hierarchy and look
/// broken next to an unshimmered name directly above.
class UserHandleText extends StatelessWidget {
  final UserData? user;

  /// Handle without the '@' when [user] has not resolved.
  final String fallback;

  final TextStyle style;
  final bool verified;
  final BadgeSize badgeSize;
  final double badgeGap;

  /// Appended after the handle — the user tile's " · bio".
  final String suffix;

  const UserHandleText({
    super.key,
    required this.user,
    required this.style,
    this.fallback = '',
    this.verified = false,
    this.badgeSize = BadgeSize.sm,
    this.badgeGap = 4,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    final handle = user?.userName ?? fallback;
    if (handle.isEmpty) return const SizedBox.shrink();
    return _NameRow(
      text: Text(
        '@$handle$suffix',
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      verified: verified,
      badgeSize: badgeSize,
      gap: badgeGap,
    );
  }
}

/// Paints its child through a sliding rainbow.
///
/// srcIn replaces the glyph colour with the gradient, so the Text's own
/// colour is ignored while this is on — and the LAYOUT is untouched, which is
/// what stops a name jumping when the document resolves mid-scroll.
class _Shimmer extends StatelessWidget {
  final Widget child;
  const _Shimmer({required this.child});

  static const List<Color> _rainbow = [
    Color(0xFFF472B6),
    Color(0xFFFBBF24),
    Color(0xFF34D399),
    Color(0xFF22D3EE),
    Color(0xFF8B5CF6),
    Color(0xFFF472B6),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _ShimmerClock.instance.phase,
      builder: (context, phase, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) {
          // Slide a repeating gradient by one full width per cycle. Repeated
          // tiling means the seam never shows.
          final shift = phase * rect.width;
          return const LinearGradient(
            colors: _rainbow,
            tileMode: TileMode.repeated,
          ).createShader(
            Rect.fromLTWH(rect.left - shift, rect.top, rect.width, rect.height),
          );
        },
        child: child,
      ),
      child: child,
    );
  }
}
