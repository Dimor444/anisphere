import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../services/my_list_service.dart';
import '../../../shared/providers/language_provider.dart';

/// Visual language for [ListStatus] — one color + icon per status, used on
/// badges, pickers and dropdowns so the list scans at a glance.
extension ListStatusUi on ListStatus {
  Color get color => switch (this) {
        ListStatus.current => AppColors.glowBlue, // blue
        ListStatus.completed => AppColors.success, // green
        ListStatus.planning => AppColors.warning, // orange
        ListStatus.dropped => AppColors.error, // red
        ListStatus.paused => AppColors.glowGold, // yellow
      };

  IconData get icon => switch (this) {
        ListStatus.current => LucideIcons.play,
        ListStatus.completed => LucideIcons.check,
        ListStatus.planning => LucideIcons.clock,
        ListStatus.dropped => LucideIcons.x,
        ListStatus.paused => LucideIcons.pause,
      };
}

/// Small colored status pill: icon + localized label.
class StatusBadge extends ConsumerWidget {
  final ListStatus status;
  final bool compact;
  const StatusBadge({super.key, required this.status, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 2 : 4),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: status.color.withOpacity(0.65)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(status.icon, size: compact ? 10 : 12, color: status.color),
        const SizedBox(width: 4),
        Text(
          ref.tr(status.trKey),
          style: TextStyle(color: status.color, fontSize: compact ? 10 : 11, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

/// Bottom-sheet status picker. Resolves to the chosen status, or null.
Future<ListStatus?> showStatusPicker(BuildContext context, {ListStatus? selected}) {
  return showModalBottomSheet<ListStatus>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Consumer(
        builder: (_, ref, __) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(ref.tr('status'), style: AppTextStyles.heading),
            ),
            for (final s in ListStatus.values)
              ListTile(
                leading: Icon(s.icon, size: 20, color: s.color),
                title: Text(ref.tr(s.trKey),
                    style: AppTextStyles.body.copyWith(
                        fontWeight: s == selected ? FontWeight.w700 : FontWeight.w400)),
                trailing: s == selected ? const Icon(LucideIcons.check, size: 18, color: AppColors.primaryLight) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

/// Error dialog for failed list operations, with an optional retry.
Future<void> showMyListError(BuildContext context, WidgetRef ref, {VoidCallback? onRetry}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        const Icon(LucideIcons.circleAlert, color: AppColors.error, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(ref.tr('myList'), style: AppTextStyles.subheading)),
      ]),
      content: Text(ref.tr('listError'), style: AppTextStyles.bodyMuted),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(ref.tr('cancel'), style: const TextStyle(color: AppColors.textSecondary)),
        ),
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onRetry();
            },
            child: Text(ref.tr('retry'), style: const TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.w700)),
          ),
      ],
    ),
  );
}
