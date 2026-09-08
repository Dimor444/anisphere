import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/aniplus_paywall.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // NOTE: every field below is screen-local and resets when this route is
  // popped — nothing reads them and nothing persists them. They are kept
  // pending a decision on what each should actually write; see the audit.
  bool _private = false;
  bool _showStreak = true;
  bool _showRank = true;
  bool _spoilerShield = true;
  /// Stored as a stable code; the label is resolved at render time.
  String _dmWho = 'everyone';
  String _birthdayVis = 'Friends';

  /// Guards the logout button while the sign-out is in flight.
  bool _loggingOut = false;

  /// Ends the Firebase session, then leaves.
  ///
  /// The order is the fix. This used to navigate to /onboarding and nothing
  /// else, so the session stayed fully authenticated: currentUser intact, the
  /// credential still in the keychain, every rule still seeing the uid. The
  /// screen said "Logout" and the backend disagreed.
  ///
  /// A failed sign-out must NOT navigate. Leaving the screen on a failure
  /// would reproduce exactly the old bug — the user believes they are out
  /// while the session lives on — so the error is surfaced and they stay put.
  Future<void> _logout() async {
    if (_loggingOut) return;
    Haptics.medium();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to sign in again to get back to your account."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx, false), child: Text(ref.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    try {
      await AuthService.instance.signOut();
    } catch (e) {
      debugPrint('[Settings] sign-out failed: $e');
      if (!mounted) return;
      setState(() => _loggingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't log out — you are still signed in. Try again.")),
      );
      return; // Deliberately no navigation: the session is still live.
    }
    if (!mounted) return;
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    // The LIVE users/{uid} doc, not the SampleData mirror. isPlus is
    // server-managed (nothing client-side can grant it), so this reads false
    // for everyone today — but it reads the real field, so the gate starts
    // working the moment a subscription can set it.
    final isPlus = myIdentity(ref)?.isPlus ?? false;
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

          _section('Privacy'),
          _switchTile('Private account', _private, (v) => setState(() => _private = v)),
          _choiceTile(ref.tr('whoCanDM'), _dmWho, const ['everyone', 'friends'],
              (v) => setState(() => _dmWho = v), labelFor: ref.tr),
          _switchTile('Show streak', _showStreak, (v) => setState(() => _showStreak = v)),
          _switchTile('Show True Fan rank', _showRank, (v) => setState(() => _showRank = v)),
          _choiceTile('Birthday visibility', _birthdayVis, ['Public', 'Friends', 'Private'], (v) => setState(() => _birthdayVis = v)),
          _switchTile('Spoiler Shield 💎', _spoilerShield, (v) {
            if (!isPlus) {
              showAniPlusPaywall(context, 'Spoiler Shield');
            } else {
              setState(() => _spoilerShield = v);
            }
          }),

          // The Notifications section stood here: five toggles and a sound
          // picker with an animated waveform. firebase_messaging is not a
          // dependency — there is no push system for any of it to configure,
          // so the switches told users a preference had been recorded when
          // nothing existed to record it against.

          _section('Language'),
          ...AppStrings.languages.map((l) {
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
          _tile(LucideIcons.ban, ref.tr('blockList'), () => context.push('/block-list')),
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

  Widget _switchTile(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        title: Text(label, style: AppTextStyles.body),
        value: value,
        onChanged: (v) {
          Haptics.light();
          onChanged(v);
        },
        activeColor: Colors.white,
        activeTrackColor: AppColors.primary,
      );

  /// [labelFor] maps an option's stored value to its display text; omit it
  /// when the value IS the label (the untranslated tiles).
  Widget _choiceTile(String label, String value, List<String> options, ValueChanged<String> onChanged,
          {String Function(String)? labelFor}) =>
      ListTile(
        title: Text(label, style: AppTextStyles.body),
        trailing: DropdownButton<String>(
          value: value,
          underline: const SizedBox.shrink(),
          dropdownColor: AppColors.surfaceAlt,
          style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(labelFor?.call(o) ?? o)))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              Haptics.select();
              onChanged(v);
            }
          },
        ),
      );
}
