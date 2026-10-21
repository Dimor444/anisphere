import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/language_provider.dart';
import '../settings/sign_out_flow.dart';

/// Shown while [AuthService.sessionUnconfirmed]: the server answered this
/// session's token check with neither a token nor a definitive "this account
/// is gone". The session is kept, because the answer may be a bad moment —
/// but if the account really is unusable, nothing will load until something
/// changes, and this is the only thing on screen that says why.
///
/// Retry asks the server again. Logout is the ordinary sign-out with its own
/// confirmation, which tells a guest the account cannot be signed back into:
/// giving the account up, and everything in it, is the player's decision,
/// never the app's. Starting over is then Continue as Guest on onboarding.
class SessionUnconfirmedBanner extends ConsumerStatefulWidget {
  const SessionUnconfirmedBanner({super.key});

  @override
  ConsumerState<SessionUnconfirmedBanner> createState() => _SessionUnconfirmedBannerState();
}

class _SessionUnconfirmedBannerState extends ConsumerState<SessionUnconfirmedBanner> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);
    await AuthService.instance.recheckSession();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.error.withOpacity(0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.cloudOff, size: 18, color: AppColors.error),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(ref.l10n.sessionUnconfirmed, style: AppTextStyles.body)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _checking ? null : () => signOutWithConfirmation(context, ref),
                  child: Text(ref.l10n.logout, style: const TextStyle(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: _checking ? null : _retry,
                  child: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(ref.l10n.retry),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
