import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_languages.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/providers/language_provider.dart';
import 'sign_out_flow.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Guards the logout button while the sign-out is in flight.
  bool _loggingOut = false;

  /// Ends the session after the player confirms; see [signOutWithConfirmation].
  Future<void> _logout() async {
    if (_loggingOut) return;
    final signedOut = await signOutWithConfirmation(context, ref,
        onSigningOut: () => setState(() => _loggingOut = true));
    if (!signedOut && mounted) setState(() => _loggingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider).code;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          // The Account and Appearance sections stood here. Every row in them
          // was inert: Edit Profile / Change Password / Linked Accounts were
          // `() {}`, the App Icon swatches moved a selection border and
          // changed no icon, and Profile Theme could not be opened by anyone
          // — its handler evaluated to null for a Plus user and showed the
          // paywall for everyone else, so no branch reached a theme picker.
          // A chevron that does nothing is worse than an absent row.

          // The Privacy section stood here: Private account, Who can DM, Show
          // streak, Show True Fan rank and Birthday visibility. All five lived
          // in this screen's state and reset when it closed; nothing saved or
          // read them. So "Private account" told a player their account was
          // private while their posts, videos, follows and profile stayed
          // readable by anyone signed in. A privacy control that does nothing
          // must not be shown. Coming back needs enforcement in the rules, not
          // a client check:
          //  - Private account: users/{uid}.isPrivate is still on the doc and
          //    read by nothing. It needs read rules on posts, ani_videos,
          //    stories and the profile that admit only approved followers, and
          //    follow requests instead of follows.
          //  - Who can DM: a stored choice the conversation create rule
          //    checks; "friends" would mean testing both follow docs there.
          //  - Show streak: currentStreak is on the user doc, which everyone
          //    signed in can read, and rules cannot hide one field of a doc —
          //    it would have to move to a doc with its own read rule.
          //  - Show True Fan rank: a stored choice the trueFanScores read rule
          //    enforces, so the leaderboard cannot read a hidden score.
          //  - Birthday visibility: a birthday. The app stores none.
          // Block List stays under More: it works, and it is a chat block —
          // the rules refuse messages in a blocked conversation — not a
          // profile one, which a Privacy heading would suggest.

          // Spoiler Shield stood here, switched on: nothing read it, so it
          // shielded nothing, and everyone without Plus — everyone — was sent
          // to a paywall for a plan nobody can buy. Spoilers are covered where
          // they are marked (posts and videos), for everyone.

          // The Notifications section stood here: five toggles and a sound
          // picker with an animated waveform. firebase_messaging is not a
          // dependency — there is no push system for any of it to configure,
          // so the switches told users a preference had been recorded when
          // nothing existed to record it against.

          _section('Language'),
          ...AppLanguages.all.map((l) {
            final sel = l.code == lang;
            return ListTile(
              leading: Text(l.flag, style: const TextStyle(fontSize: 22)),
              title: Text(l.name, style: AppTextStyles.body),
              subtitle: l.isRTL ? const Text('Switches to RTL', style: AppTextStyles.captionMuted) : null,
              trailing: sel ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
              onTap: () {
                Haptics.select();
                ref.read(languageProvider.notifier).setLanguage(l.code);
              },
            );
          }),

          _section('More'),
          _tile(LucideIcons.ban, ref.l10n.blockList, () => context.push('/block-list')),
          // Report a Problem, About and Terms & Privacy were all `() {}`, and
          // Apply for Press Pass showed a snackbar claiming an application had
          // "opened" while submitting nothing — under a hardcoded "Eligible"
          // badge with no check behind it.
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              onTap: _loggingOut ? null : _logout,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.error.withOpacity(0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.error.withOpacity(0.4))),
                child: _loggingOut
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error),
                      )
                    : Text('Logout', style: AppTextStyles.subheading.copyWith(color: AppColors.error)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
              onPressed: _loggingOut
                  ? null
                  : () {
                      Haptics.medium();
                      context.push('/delete-account');
                    },
              icon: const Icon(LucideIcons.trash2, size: 16, color: AppColors.error),
              label: Text(ref.l10n.deleteAccount,
                  style: AppTextStyles.body.copyWith(color: AppColors.error, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(t, style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      );

  Widget _tile(IconData icon, String label, VoidCallback? onTap, {Widget? trailing}) => ListTile(
        leading: Icon(icon, size: 20, color: AppColors.textSecondary),
        title: Text(label, style: AppTextStyles.body),
        trailing: trailing ?? const Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textMuted),
        onTap: onTap,
      );

}
