import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/dm_conversation.dart';
import '../../services/auth_service.dart';
import '../../services/dm_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';

/// Live DM threads for the signed-in user, most recently active first.
/// One Firestore listener behind the provider; every row resolves the
/// counterpart's name/avatar/badge at render time through identityProvider —
/// nothing is denormalized on the conversation doc.
final _conversationsProvider =
    StreamProvider.autoDispose<List<DmConversation>>((ref) async* {
  final uid = (await AuthService.instance.initAuth()).uid;
  yield* DmService.instance.watchConversations(uid);
});

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convos = ref.watch(_conversationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        // Compose lands with the people picker in a later phase.
        actions: [IconButton(icon: const Icon(LucideIcons.pencil, size: 20), onPressed: () {})],
      ),
      body: convos.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const _Note(
          icon: LucideIcons.wifiOff,
          title: 'Messages are unavailable right now.',
          caption: 'Check your connection and try again.',
        ),
        data: (list) {
          if (list.isEmpty) {
            return const _Note(
              icon: LucideIcons.messageCircle,
              title: 'No messages yet',
              caption: 'Conversations you start will show up here.',
            );
          }
          final me = AuthService.instance.uid ?? '';
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(indent: 78, height: 1),
            itemBuilder: (_, i) => _ConversationTile(convo: list[i], me: me),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends ConsumerStatefulWidget {
  final DmConversation convo;
  final String me;
  const _ConversationTile({required this.convo, required this.me});

  @override
  ConsumerState<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends ConsumerState<_ConversationTile> {
  late Future<int> _unread = _fetchUnread();

  Future<int> _fetchUnread() =>
      DmService.instance.unreadCount(widget.convo.id, widget.me);

  @override
  void didUpdateWidget(_ConversationTile old) {
    super.didUpdateWidget(old);
    // Re-count only when the thread actually moved — every snapshot rebuilds
    // the list, and re-running an aggregation per rebuild would be waste.
    if (old.convo.updatedAt != widget.convo.updatedAt ||
        old.convo.id != widget.convo.id) {
      _unread = _fetchUnread();
    }
  }

  @override
  Widget build(BuildContext context) {
    final convo = widget.convo;
    final otherUid = convo.otherUid(widget.me);
    // Live users/{uid} doc; '' fallbacks paint a placeholder row until the
    // first snapshot lands (or the counterpart's account is gone).
    final other = identityOf(ref, otherUid);
    final name = other?.nameToShow ?? '';

    return InkWell(
      onTap: () {
        Haptics.light();
        context.push('/chat/${convo.id}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              name: name.isEmpty ? '?' : name,
              imageUrl: other?.userAvatar,
              radius: 26,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? 'Anime fan' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.subheading,
                      ),
                    ),
                    if (other?.isVerified == true) ...[
                      const SizedBox(width: 4),
                      const VerifiedBadge(size: BadgeSize.sm),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    convo.lastMessage.isEmpty ? 'Say hi 👋' : convo.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  convo.updatedAt == null ? '' : Fmt.timeAgo(convo.updatedAt!),
                  style: AppTextStyles.captionMuted,
                ),
                const SizedBox(height: 6),
                FutureBuilder<int>(
                  future: _unread,
                  builder: (_, snap) => (snap.data ?? 0) > 0
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox(width: 10, height: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Centered icon + title + caption, shared by the empty and error states.
class _Note extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  const _Note({required this.icon, required this.title, required this.caption});

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
