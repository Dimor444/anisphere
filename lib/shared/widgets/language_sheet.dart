import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/anisphere_logo.dart';
import '../providers/language_provider.dart';

/// Bottom sheet to pick the app language. Selecting Arabic flips to RTL app-wide.
void showLanguageSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    // Without this the sheet is capped at 9/16 of the screen, which is less
    // than the language list needs on every device we support.
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends ConsumerWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(languageProvider).code;
    // Leave the sheet short of full height so the scrim stays tappable to
    // dismiss, and so it still reads as a sheet rather than a page.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 14),
            Text(ref.tr('selectLanguage'), style: AppTextStyles.heading),
            const SizedBox(height: 8),
            // Flexible + shrinkWrap: the list takes only the height it needs
            // when it fits, so the sheet still hugs its content, and scrolls
            // instead of overflowing when it does not — which is the case at
            // large text sizes and on short devices.
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: AppStrings.languages.map((l) {
                  final selected = l.code == current;
                  return ListTile(
                    leading: Text(l.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(l.name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                    subtitle: l.isRTL ? const Text('RTL', style: AppTextStyles.captionMuted) : null,
                    trailing: selected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                        : null,
                    onTap: () {
                      Haptics.select();
                      ref.read(languageProvider.notifier).setLanguage(l.code);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Human-readable language name for a code (used in splash + sign-up).
String languageName(String code) => AppStrings.languages
    .firstWhere((l) => l.code == code, orElse: () => AppStrings.languages[1])
    .name;

/// The AniSphere logo mark: the ∞-merged-with-A gradient glyph.
///
/// Backwards-compatible shim — delegates to [AniSphereLogo] so every existing
/// `AniLogo(...)` call site picks up the new brand mark.
class AniLogo extends StatelessWidget {
  final double size;
  const AniLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => AniSphereLogo(size: size);
}
