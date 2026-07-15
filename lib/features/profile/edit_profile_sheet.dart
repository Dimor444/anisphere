import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/user.dart';
import '../../data/models/user_profile.dart';
import '../../services/follow_service.dart';
import '../../services/profile_repository.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/gradient_button.dart';
import '../../shared/widgets/user_avatar.dart';
import 'widgets/username_field.dart';

/// Edit Profile — owner edit of @username (unique handle), displayName and
/// bio. Avatar upload lands with Firebase Storage; until then the sheet
/// previews initials only.
///
/// Prefills from the live `users/{uid}` profile. A changed handle claims
/// through [FollowService.claimUserName] (transactional, unique); the rest
/// saves through [FollowService.updateProfile], which writes ONLY
/// displayName + bio — never isVerified, isPlus, or counters (rules block
/// those anyway).
Future<void> showEditProfileSheet(BuildContext context) {
  Haptics.light();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _EditProfileSheet(),
  );
}

/// First letters of up to two words, uppercased — mirrors
/// [UserProfile.initials] but works on the name being typed.
String _initialsOf(String name) {
  final letters = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();
  return letters.isEmpty ? '?' : letters;
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet();

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  static const int maxNameLength = 30;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _userName = TextEditingController();
  final TextEditingController _bio = TextEditingController();

  bool _loaded = false;
  bool _saving = false;
  String? _error;

  /// The handle currently claimed in Firestore — save skips the claim
  /// transaction when the field still holds it.
  String _currentHandle = '';
  HandleStatus _handleStatus = HandleStatus.unchanged;

  @override
  void initState() {
    super.initState();
    ProfileRepository.instance.watchProfile().first.then((UserProfile? p) {
      if (!mounted) return;
      setState(() {
        _name.text = p?.displayName ?? '';
        _bio.text = p?.bio ?? '';
        _currentHandle = p?.userName ?? '';
        _userName.text = _currentHandle;
        _loaded = true;
      });
    }).catchError((Object e) {
      // Prefill stays empty — the user can still type and save.
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _userName.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= maxNameLength &&
      _handleStatus.ok;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmation = ref.tr('profileUpdated');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Claim the handle first (transactional) so a taken name fails the
      // save before anything else is written.
      final handle = _userName.text.trim();
      if (handle.isNotEmpty && handle != _currentHandle) {
        await FollowService.instance.claimUserName(handle);
        _currentHandle = handle;
      }
      await FollowService.instance.updateProfile(
        displayName: _name.text,
        bio: _bio.text.trim(),
      );
      Haptics.medium();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(confirmation)));
    } on UserNameTakenException {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '@${_userName.text.trim()} — ${ref.tr('usernameTaken').toLowerCase()}';
      });
    } catch (_) {
      // Keep the sheet (and the user's input) — just surface the failure.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ref.tr('actionFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 20),
      child: !_loaded
          ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ref.tr('editProfile'), style: AppTextStyles.subheading),
                const SizedBox(height: 14),
                Row(children: [
                  UserAvatar(name: _name.text, initials: _initialsOf(_name.text), radius: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: 0.5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          const Icon(LucideIcons.camera, size: 16, color: AppColors.textMuted),
                          const SizedBox(width: 8),
                          Flexible(child: Text(ref.tr('uploadPhotoSoon'), style: AppTextStyles.captionMuted)),
                        ]),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text(ref.tr('username'), style: AppTextStyles.label),
                const SizedBox(height: 6),
                UserNameField(
                  controller: _userName,
                  currentHandle: _currentHandle,
                  onStatus: (s) => setState(() => _handleStatus = s),
                ),
                const SizedBox(height: 10),
                Text(ref.tr('displayName'), style: AppTextStyles.label),
                const SizedBox(height: 6),
                TextField(
                  controller: _name,
                  maxLength: maxNameLength,
                  autofocus: true,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(hintText: ref.tr('displayName'), counterText: ''),
                  onChanged: (_) => setState(() {}), // re-validate + refresh initials preview
                ),
                const SizedBox(height: 10),
                Text(ref.tr('bio'), style: AppTextStyles.label),
                const SizedBox(height: 6),
                TextField(
                  controller: _bio,
                  maxLength: UserData.maxBioLength,
                  maxLines: 3,
                  style: AppTextStyles.body,
                  decoration: InputDecoration(hintText: ref.tr('bio')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: AppTextStyles.caption.copyWith(color: AppColors.error)),
                ],
                const SizedBox(height: 14),
                GradientButton(
                  label: ref.tr('save'),
                  onPressed: _valid && !_saving ? _save : null,
                ),
              ],
            ),
    );
  }
}
