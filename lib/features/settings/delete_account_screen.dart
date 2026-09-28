import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/language_provider.dart';

/// The one way into account deletion. A full page, not a dialog: what goes,
/// what stays and what cannot be undone all need saying before anyone agrees,
/// and a dialog is built to be dismissed with a tap.
///
/// The typed word is DELETE in every language. It is the confirmation, not
/// copy — the same token in every locale is what makes it unambiguous — and
/// the prompt around it is translated.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  static const _token = 'DELETE';

  final _confirm = TextEditingController();
  bool _deleting = false;

  /// The last failure's message, shown under the button until the next try.
  /// Inline rather than a snackbar: it is the answer to what the user just
  /// did, and it has to still be there when they look back up.
  String? _error;

  bool get _armed => _confirm.text.trim() == _token;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting || !_armed) return;
    Haptics.heavy();
    FocusScope.of(context).unfocus();
    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      await AuthService.instance.deleteAccount();
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = ref.tr(switch (e.failure) {
          AccountDeletionFailure.unreachable => 'deleteFailedUnreachable',
          AccountDeletionFailure.refused => 'deleteFailedNothingChanged',
          AccountDeletionFailure.unconfirmed => 'deleteFailedUnsure',
        });
      });
      return;
    } catch (e) {
      // Anything else escaped after the call was answered — most plausibly
      // the sign-out itself. Whether the account went is unknown, and
      // retrying is safe either way.
      debugPrint('[DeleteAccount] unexpected failure: $e');
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = ref.tr('deleteFailedUnsure');
      });
      return;
    }

    if (!mounted) return;
    // The root messenger, captured before the route goes: it outlives this
    // page, so the notice lands on onboarding.
    final messenger = ScaffoldMessenger.of(context);
    final notice = ref.tr('accountDeletionStarted');
    context.go('/onboarding');
    messenger.showSnackBar(SnackBar(content: Text(notice)));
    // After the frame that tears the signed-in screens down, so none of them
    // can touch Firestore between the terminate and the wipe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AuthService.instance.clearLocalData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // No leaving mid-call: the outcome has to land somewhere the user sees.
      canPop: !_deleting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ref.tr('deleteAccount')),
          automaticallyImplyLeading: !_deleting,
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Text(ref.tr('deleteAccountLead'), style: AppTextStyles.body),
              _heading(ref.tr('deleteWhatGoes')),
              _point(LucideIcons.fileX, ref.tr('deleteGoesContent')),
              _point(LucideIcons.heartOff, ref.tr('deleteGoesActivity')),
              _point(LucideIcons.coins, ref.tr('deleteGoesWallet')),
              _heading(ref.tr('deleteWhatStays')),
              _point(LucideIcons.messagesSquare, ref.tr('deleteOthersKeep')),
              _point(LucideIcons.atSign, ref.tr('deleteHandleRetired')),
              _heading(ref.tr('deleteWhen')),
              _point(LucideIcons.clock, ref.tr('deleteTiming')),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.error.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(ref.tr('deleteIrreversible'),
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.error, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Text(ref.tr('deleteTypeToConfirm'), style: AppTextStyles.caption),
              const SizedBox(height: 8),
              TextField(
                controller: _confirm,
                enabled: !_deleting,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                style: AppTextStyles.subheading.copyWith(letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: _token,
                  hintStyle: AppTextStyles.subheading
                      .copyWith(color: AppColors.textMuted, letterSpacing: 2),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.error),
                  ),
                ),
                onSubmitted: (_) => _delete(),
              ),
              // Above the button, not under it: below, it lands past the
              // fold on a phone and the user is left looking at a button
              // that silently came back.
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              _button(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button() {
    final enabled = _armed && !_deleting;
    return GestureDetector(
      onTap: enabled ? _delete : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _armed || _deleting ? 1 : 0.4,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _deleting
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(ref.tr('deletingAccount'),
                      style: AppTextStyles.subheading.copyWith(color: Colors.white)),
                ])
              : Text(ref.tr('deleteAccountButton'),
                  style: AppTextStyles.subheading.copyWith(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _heading(String t) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(t,
            style: AppTextStyles.caption.copyWith(
                color: AppColors.primaryLight, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      );

  Widget _point(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTextStyles.body)),
        ]),
      );
}
