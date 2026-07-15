import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/user.dart';
import '../../services/follow_service.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';

/// Debounced @handle search in a bottom sheet; resolves to the picked user
/// (or null). Backed by the shared [FollowService.searchUsers] prefix search
/// — the same path the Discover user search uses.
Future<UserData?> showMentionPickerSheet(BuildContext context) {
  return showModalBottomSheet<UserData>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _MentionPickerSheet(),
  );
}

class _MentionPickerSheet extends ConsumerStatefulWidget {
  const _MentionPickerSheet();

  @override
  ConsumerState<_MentionPickerSheet> createState() => _MentionPickerSheetState();
}

class _MentionPickerSheetState extends ConsumerState<_MentionPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<UserData> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      final results = await FollowService.instance.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            const SizedBox(height: 14),
            Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _onChanged,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: ref.tr('searchUsers'),
                  prefixIcon: const Icon(LucideIcons.atSign, size: 18),
                  isDense: true,
                ),
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final u = _results[i];
                  return ListTile(
                    leading: UserAvatar(name: u.nameToShow, imageUrl: u.userAvatar, radius: 18),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text('@${u.userName}',
                              style: AppTextStyles.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (u.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: BadgeSize.sm),
                        ],
                      ],
                    ),
                    subtitle: Text(u.displayName,
                        style: AppTextStyles.captionMuted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Haptics.light();
                      Navigator.pop(context, u);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
