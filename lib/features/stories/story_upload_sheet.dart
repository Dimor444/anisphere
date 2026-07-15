import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../shared/providers/language_provider.dart';
import 'story_editor_screen.dart';

/// "Add Story" flow: choose camera or gallery (phase 1) → pick one image →
/// full-screen editor with text overlays (phase 2), which flattens, runs the
/// shared compression pipeline (JPEG, hard < 1 MB) and uploads.
Future<void> startStoryUpload(BuildContext context, WidgetRef ref) async {
  Haptics.light();
  final messenger = ScaffoldMessenger.of(context);
  final failedLabel = ref.tr('actionFailed');
  final cancelLabel = ref.tr('cancel');

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _StorySourceSheet(cancelLabel: cancelLabel),
  );
  if (source == null || !context.mounted) return;

  final XFile? picked;
  try {
    picked = await ImagePicker().pickImage(source: source);
  } on PlatformException catch (e) {
    // OS-level permission denial — point at Settings instead of a generic
    // failure. The other source stays usable on the next "Add Story" tap.
    final message = switch (e.code) {
      'camera_access_denied' => 'Camera access is off. Enable it in Settings, or choose from your gallery.',
      'photo_access_denied' => 'Photo access is off. Enable it in Settings, or use the camera.',
      _ => failedLabel,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return;
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failedLabel)));
    return;
  }
  if (picked == null || !context.mounted) return;

  final imageFile = File(picked.path);
  await Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => StoryEditorScreen(imageFile: imageFile),
  ));
}

/// Composer phase 1: where does the story photo come from? Pops with the
/// chosen [ImageSource], or null when dismissed. A richer in-app camera
/// (live preview) is a later phase — this stays a thin front door over
/// image_picker.
class _StorySourceSheet extends StatelessWidget {
  final String cancelLabel;
  const _StorySourceSheet({required this.cancelLabel});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('New Story', style: AppTextStyles.heading),
            const SizedBox(height: 4),
            _SourceOption(
              icon: LucideIcons.camera,
              label: 'Take a photo',
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            _SourceOption(
              icon: LucideIcons.image,
              label: 'Choose from gallery',
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            _SourceOption(
              icon: LucideIcons.x,
              label: cancelLabel,
              muted: true,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool muted;
  final VoidCallback onTap;
  const _SourceOption({required this.icon, required this.label, required this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: muted ? AppColors.textSecondary : AppColors.primaryLight),
      title: Text(label,
          style: AppTextStyles.body.copyWith(color: muted ? AppColors.textSecondary : AppColors.textPrimary)),
      onTap: () {
        Haptics.light();
        onTap();
      },
    );
  }
}

