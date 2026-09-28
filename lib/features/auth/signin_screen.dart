import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/language_sheet.dart';
import 'social_buttons.dart';

/// Whether the auth screens offer accounts: email + password sign-in, the
/// Create Account flow (and its `/signup` route), and the Google / Apple
/// buttons.
///
/// None of them did anything. Sign In ignored what was typed and went to the
/// feed. Create Account collected an email, a password, a date of birth and
/// five anime, then went to the feed having created and saved nothing. Google
/// and Apple showed "(demo)". Anonymous guest is the only identity that
/// exists — and a guest who signs out can never get back in, so a user who
/// believed they had a password lost everything they made. The screens are
/// kept, not deleted.
///
/// Real accounts need, before this can be true:
/// - Firebase Auth providers turned on — email/password, and Google / Apple
///   with their iOS setup (URL scheme, the Sign in with Apple capability;
///   App Store rules require an equivalent privacy-focused option, such as
///   Apple, once Google is offered).
/// - Linking, not replacing: `linkWithCredential` on the current guest, so the
///   uid — and every post, list entry and balance keyed to it — carries over,
///   with a path for "credential already in use".
/// - Email verification and password reset ("Forgot password?" is a no-op).
/// - An age gate where the account is actually made. The date-of-birth check
///   lived in the Create Account flow, which made nothing; the guest path has
///   never had one.
/// - Somewhere for the onboarding taste picks to go. They were sample-anime
///   ids, not AniList ids, and no field on users/{uid} holds them.
const bool kAccountAuthEnabled = false;

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _obscure = true;
  bool _guestLoading = false;

  Future<void> _continueAsGuest() async {
    Haptics.medium();
    setState(() => _guestLoading = true);
    try {
      final user = await AuthService.instance.signInAsGuest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${ref.tr('guestSignedIn')} · ${user.uid}'),
        behavior: SnackBarBehavior.floating,
      ));
      context.go('/feed');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.tr('guestError')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _guestLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackButton()),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 10),
            const Center(child: AniLogo(size: 78)),
            const SizedBox(height: 22),
            if (kAccountAuthEnabled) ...[
              const Text('Welcome back', style: AppTextStyles.display),
              const Text('Sign in to your AniSphere', style: AppTextStyles.bodyMuted),
              const SizedBox(height: 26),
              TextField(
                decoration: InputDecoration(
                  labelText: ref.tr('email'),
                  prefixIcon: const Icon(LucideIcons.mail, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: ref.tr('password'),
                  prefixIcon: const Icon(LucideIcons.lock, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? LucideIcons.eye : LucideIcons.eyeOff, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () {},
                  child: Text('Forgot password?', style: AppTextStyles.caption.copyWith(color: AppColors.primaryLight)),
                ),
              ),
              const SizedBox(height: 6),
              GradientButton(
                label: ref.tr('signIn'),
                onPressed: () {
                  Haptics.medium();
                  context.go('/feed');
                },
              ),
              const SizedBox(height: 22),
              const Row(children: [
                Expanded(child: Divider()),
                Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: AppTextStyles.captionMuted)),
                Expanded(child: Divider()),
              ]),
              const SizedBox(height: 18),
              const SocialButtons(),
              const SizedBox(height: 14),
            ] else ...[
              Text(ref.tr('guestIntroTitle'), style: AppTextStyles.display),
              const SizedBox(height: 8),
              Text(ref.tr('guestIntroBody'), style: AppTextStyles.bodyMuted),
              const SizedBox(height: 18),
              // Said BEFORE the tap, not only at sign-out: this is the choice
              // that cannot be undone.
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.warning.withOpacity(0.6)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(LucideIcons.alertTriangle, size: 18, color: AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(ref.tr('guestIntroWarning'), style: AppTextStyles.body)),
                ]),
              ),
              const SizedBox(height: 22),
            ],
            OutlinedButton.icon(
              onPressed: _guestLoading ? null : _continueAsGuest,
              icon: _guestLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight))
                  : const Icon(LucideIcons.ghost, size: 18, color: AppColors.primaryLight),
              label: Text(ref.tr('continueAsGuest'),
                  style: AppTextStyles.label.copyWith(color: AppColors.primaryLight)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (kAccountAuthEnabled) ...[
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/signup'),
                  child: RichText(
                    text: TextSpan(style: AppTextStyles.body, children: [
                      const TextSpan(text: "New here?  ", style: TextStyle(color: AppColors.textSecondary)),
                      TextSpan(text: ref.tr('createAccount'), style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
