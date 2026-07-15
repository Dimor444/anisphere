import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../services/follow_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import 'widgets/username_field.dart';

/// First-launch @username gate: accounts whose handle isn't claimed in the
/// usernames/ registry yet (all pre-handle accounts, and fresh ones with the
/// generated placeholder) pick one here before continuing.
///
/// Not dismissable by swipe/back — but never a hard lock: any claim failure
/// (taken, rules reject, network blip) surfaces inline and the button stays
/// retryable. The launch-time caller skips the gate entirely when even the
/// needs-claim check can't run (offline) and re-prompts next launch.
Future<void> showClaimUserNameSheet(BuildContext context, {required String suggested}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => PopScope(canPop: false, child: _ClaimSheet(suggested: suggested)),
  );
}

class _ClaimSheet extends ConsumerStatefulWidget {
  final String suggested;
  const _ClaimSheet({required this.suggested});

  @override
  ConsumerState<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<_ClaimSheet> {
  late final TextEditingController _handle = TextEditingController(text: widget.suggested);

  // currentHandle stays '' on purpose: even a prefilled existing handle must
  // run the availability check and be claimed — that's the whole gate.
  HandleStatus _status = HandleStatus.unchanged;
  bool _claiming = false;
  String? _error;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    setState(() {
      _claiming = true;
      _error = null;
    });
    try {
      await FollowService.instance.claimUserName(_handle.text.trim());
      Haptics.medium();
      if (mounted) Navigator.pop(context);
    } on UserNameTakenException {
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = '@${_handle.text.trim()} — ${ref.tr('usernameTaken').toLowerCase()}';
      });
    } catch (_) {
      // Transient failure (network, rules) — inline error, button stays
      // retryable, never a locked sheet.
      if (!mounted) return;
      setState(() {
        _claiming = false;
        _error = ref.tr('usernameClaimFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 20, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ref.tr('claimUsernameTitle'), style: AppTextStyles.subheading),
          const SizedBox(height: 6),
          Text(ref.tr('claimUsernameBody'), style: AppTextStyles.captionMuted),
          const SizedBox(height: 14),
          UserNameField(
            controller: _handle,
            onStatus: (s) => setState(() => _status = s),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 14),
          GradientButton(
            label: ref.tr('claim'),
            onPressed: _status == HandleStatus.available && !_claiming ? _claim : null,
          ),
          // Availability can't be verified (offline / backend unreachable):
          // never hold the whole app hostage behind an uncompletable gate.
          // The launch caller re-prompts next time; barrier/drag/back stay
          // disabled — this is the only exit, and only in the error state.
          if (_status == HandleStatus.error) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () {
                  Haptics.light();
                  Navigator.pop(context);
                },
                child: Text(ref.tr('claimLater')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
