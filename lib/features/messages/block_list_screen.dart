import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/dm_conversation.dart';
import '../../services/auth_service.dart';
import '../../services/dm_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_avatar.dart';

/// Conversations the signed-in user has blocked. Blocking is per-thread
/// (the blockedBy array on the conversation doc), so this is the list of
/// people they can't exchange messages with — unblocking here lifts only
/// the caller's own entry, exactly like the chat screen's menu.
final _blockedProvider =
    StreamProvider.autoDispose<List<DmConversation>>((ref) async* {
  final uid = (await AuthService.instance.initAuth()).uid;
  yield* DmService.instance.watchBlockedConversations(uid);
});

class BlockListScreen extends ConsumerWidget {
  const BlockListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(_blockedProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Block List')),
      body: blocked.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const _Empty(
          icon: LucideIcons.wifiOff,
          title: 'Block list unavailable',
          caption: 'Check your connection and try again.',
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _Empty(
              icon: LucideIcons.ban,
              title: 'No blocked conversations',
              caption: 'People you block from a chat will appear here.',
            );
          }
          final me = AuthService.instance.uid ?? '';
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(indent: 72, height: 1),
            itemBuilder: (_, i) => _BlockedTile(convo: list[i], me: me),
          );
        },
      ),
    );
  }
}

class _BlockedTile extends ConsumerStatefulWidget {
  final DmConversation convo;
  final String me;
  const _BlockedTile({required this.convo, required this.me});

  @override
  ConsumerState<_BlockedTile> createState() => _BlockedTileState();
}

class _BlockedTileState extends ConsumerState<_BlockedTile> {
  bool _busy = false;

  Future<void> _unblock() async {
    if (_busy) return;
    setState(() => _busy = true);
    Haptics.light();
    try {
      // The row disappears on its own: the stream stops matching once the
      // caller's uid leaves blockedBy.
      await DmService.instance.setBlocked(widget.convo.id, false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.tr('actionFailed')),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherUid = widget.convo.otherUid(widget.me);
    final other = otherUid.isEmpty ? null : identityOf(ref, otherUid);
    final name = other?.nameToShow ?? '';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: UserAvatar(
        name: name.isEmpty ? '?' : name,
        imageUrl: other?.userAvatar,
        radius: 22,
      ),
      title: Text(name.isEmpty ? 'Anime fan' : name,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.subheading),
      subtitle: other == null
          ? null
          : Text('@${other.userName}', style: AppTextStyles.captionMuted),
      trailing: TextButton(
        onPressed: _busy ? null : _unblock,
        child: Text(
          _busy ? 'Unblocking…' : 'Unblock',
          style: AppTextStyles.body.copyWith(
            color: _busy ? AppColors.textMuted : AppColors.primaryLight,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  const _Empty({required this.icon, required this.title, required this.caption});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.subheading),
            const SizedBox(height: 6),
            Text(caption, textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
          ],
        ),
      ),
    );
  }
}
