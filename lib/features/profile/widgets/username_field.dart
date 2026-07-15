import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../services/follow_service.dart';
import '../../../shared/providers/language_provider.dart';

/// Status of the handle currently typed into a [UserNameField].
enum HandleStatus { unchanged, tooShort, invalid, reserved, checking, available, taken, error }

extension HandleStatusX on HandleStatus {
  /// The handle may be submitted: it's the caller's current one, or free.
  bool get ok => this == HandleStatus.unchanged || this == HandleStatus.available;
}

/// @handle input with live availability: lowercase-filtered typing, a
/// debounced usernames/{handle} lookup, and a status line underneath.
/// Instant feedback only — enforcement lives in firestore.rules and
/// [FollowService.claimUserName].
class UserNameField extends ConsumerStatefulWidget {
  final TextEditingController controller;

  /// The caller's currently claimed handle ('' when none) — typing it back
  /// counts as [HandleStatus.unchanged] and skips the lookup.
  final String currentHandle;
  final ValueChanged<HandleStatus> onStatus;

  const UserNameField({
    super.key,
    required this.controller,
    required this.onStatus,
    this.currentHandle = '',
  });

  @override
  ConsumerState<UserNameField> createState() => _UserNameFieldState();
}

class _UserNameFieldState extends ConsumerState<UserNameField> {
  static final _lowercase = TextInputFormatter.withFunction(
      (oldValue, newValue) => newValue.copyWith(text: newValue.text.toLowerCase()));

  HandleStatus _status = HandleStatus.unchanged;
  Timer? _debounce;
  int _seq = 0; // drops out-of-order availability results

  @override
  void initState() {
    super.initState();
    // Classify the prefill; parent may still be building, so notify after
    // the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onChanged(widget.controller.text);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _set(HandleStatus s) {
    if (!mounted || s == _status) return;
    setState(() => _status = s);
    widget.onStatus(s);
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    _seq++;
    final h = raw.trim();
    if (h.isNotEmpty && h == widget.currentHandle) return _set(HandleStatus.unchanged);
    if (h.length < 3) return _set(HandleStatus.tooShort);
    if (!FollowService.handlePattern.hasMatch(h)) return _set(HandleStatus.invalid);
    if (FollowService.reservedHandles.contains(h)) return _set(HandleStatus.reserved);
    _set(HandleStatus.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () => _check(h));
  }

  Future<void> _check(String h) async {
    final seq = _seq;
    try {
      final free = await FollowService.instance.isUserNameAvailable(h);
      if (seq != _seq) return; // typed again meanwhile
      _set(free ? HandleStatus.available : HandleStatus.taken);
    } catch (_) {
      if (seq != _seq) return;
      _set(HandleStatus.error);
    }
  }

  (String, Color) get _statusLine => switch (_status) {
        HandleStatus.unchanged => ('', AppColors.textMuted),
        HandleStatus.tooShort => (ref.tr('usernameTooShort'), AppColors.textMuted),
        HandleStatus.invalid => (ref.tr('usernameInvalid'), AppColors.error),
        HandleStatus.reserved => (ref.tr('usernameReserved'), AppColors.error),
        HandleStatus.checking => (ref.tr('usernameChecking'), AppColors.textMuted),
        HandleStatus.available => (ref.tr('usernameAvailable'), AppColors.success),
        HandleStatus.taken => (ref.tr('usernameTaken'), AppColors.error),
        HandleStatus.error => (ref.tr('usernameCheckFailed'), AppColors.error),
      };

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusLine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLength: 20,
          style: AppTextStyles.body,
          inputFormatters: [
            _lowercase,
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
          ],
          decoration: InputDecoration(
            hintText: ref.tr('username').toLowerCase(),
            prefixText: '@',
            counterText: '',
          ),
          onChanged: _onChanged,
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ],
    );
  }
}
