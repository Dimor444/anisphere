import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/glass_modals.dart';

/// Asks, then ends the Firebase session and leaves for onboarding. Settings'
/// Logout and the shell's "can't confirm your account" banner both come
/// through here, so leaving an account always means the same question.
///
/// The order is the fix. This used to navigate to /onboarding and nothing
/// else, so the session stayed fully authenticated: currentUser intact, the
/// credential still in the keychain, every rule still seeing the uid. The
/// screen said "Logout" and the backend disagreed.
///
/// A failed sign-out must NOT navigate. Leaving the screen on a failure
/// would reproduce exactly the old bug — the user believes they are out
/// while the session lives on — so the error is surfaced and they stay put.
///
/// [onSigningOut] runs once the player has confirmed, before the sign-out
/// starts — for a caller that shows progress. Returns true once signed out.
Future<bool> signOutWithConfirmation(BuildContext context, WidgetRef ref,
    {VoidCallback? onSigningOut}) async {
  Haptics.medium();

  final confirmed = AuthService.instance.isGuest
      ? await _confirmGuestSignOut(context, ref)
      : await showGlassDialog<bool>(
          context: context,
          builder: (dCtx) => AlertDialog(
            title: const Text('Log out?'),
            content: const Text("You'll need to sign in again to get back to your account."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(ref.l10n.cancel)),
              TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Log out')),
            ],
          ),
        );
  if (confirmed != true || !context.mounted) return false;

  onSigningOut?.call();
  try {
    await AuthService.instance.signOut();
  } catch (e) {
    debugPrint('[SignOut] sign-out failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't log out — you are still signed in. Try again.")),
      );
    }
    return false; // Deliberately no navigation: the session is still live.
  }
  if (context.mounted) context.go('/onboarding');
  return true;
}

/// A guest cannot sign back in — there is no credential to sign in WITH —
/// so signing out abandons the account with everything it posted still
/// online and nobody able to remove it. Said plainly, with deletion
/// offered in the same breath. True for every account today: guest is the
/// only identity there is.
///
/// Returns true only for "Sign out anyway". "Delete account" opens the
/// delete page instead and reports false, so the sign-out does not run.
Future<bool> _confirmGuestSignOut(BuildContext context, WidgetRef ref) async {
  final choice = await showGlassDialog<String>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(ref.l10n.guestSignOutTitle),
      content: Text(ref.l10n.guestSignOutBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(ref.l10n.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(dCtx, 'delete'),
          child: Text(ref.l10n.deleteAccount, style: const TextStyle(color: AppColors.error)),
        ),
        TextButton(onPressed: () => Navigator.pop(dCtx, 'signout'), child: Text(ref.l10n.signOutAnyway)),
      ],
    ),
  );
  if (choice == 'delete' && context.mounted) context.push('/delete-account');
  return choice == 'signout';
}
