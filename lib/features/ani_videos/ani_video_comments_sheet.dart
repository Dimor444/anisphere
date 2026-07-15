import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/ani_video.dart';
import '../../data/models/post.dart';
import '../../services/ani_video_service.dart';
import '../../services/auth_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_avatar.dart';

/// Comments for one Ani Video — bottom sheet over the playing video, same
/// real-time behavior as the feed's post detail comments.
void showAniVideoCommentsSheet(BuildContext context, AniVideoData video) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _CommentsSheet(video: video),
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  final AniVideoData video;
  const _CommentsSheet({required this.video});

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  static const int _page = 30;

  final _ctrl = TextEditingController();
  int _limit = _page;
  bool _sending = false;

  String get _uid => AuthService.instance.uid ?? '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    Haptics.light();
    setState(() => _sending = true);
    try {
      await AniVideoService.instance.addComment(widget.video.id, text);
      if (!mounted) return;
      _ctrl.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.tr('actionFailed')),
        action: SnackBarAction(label: ref.tr('retry'), onPressed: _send),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CommentData c) async {
    try {
      await AniVideoService.instance.deleteComment(widget.video.id, c.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('actionFailed'))));
    }
  }

  /// Pending server timestamps (null createdAt) on top — they're ours.
  List<CommentData>? _sorted(List<CommentData>? comments) {
    if (comments == null) return null;
    final list = [...comments];
    list.sort((a, b) {
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final me = myIdentity(ref);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.65,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Text(ref.tr('comments'), style: AppTextStyles.subheading),
            const SizedBox(height: 4),
            Expanded(
              child: StreamBuilder<List<CommentData>>(
                stream: AniVideoService.instance.getComments(widget.video.id, limit: _limit),
                builder: (context, snap) {
                  final comments = _sorted(snap.data);
                  if (comments == null) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  if (comments.isEmpty) {
                    return Center(child: Text(ref.tr('noCommentsYet'), style: AppTextStyles.captionMuted));
                  }
                  return ListView(
                    padding: const EdgeInsets.only(top: 6, bottom: 12),
                    children: [
                      for (final c in comments)
                        _CommentTile(
                          comment: c,
                          canDelete: c.userId == _uid || widget.video.userId == _uid,
                          onDelete: () => _delete(c),
                        ),
                      if (comments.length >= _limit)
                        TextButton(
                          onPressed: () => setState(() => _limit += _page),
                          child: Text(ref.tr('comments'),
                              style: const TextStyle(color: AppColors.primaryLight)),
                        ),
                    ],
                  );
                },
              ),
            ),
            // Composer, pinned above the keyboard.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    UserAvatar(name: me?.nameToShow ?? '', imageUrl: me?.userAvatar, radius: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        maxLength: CommentData.maxContentLength,
                        style: AppTextStyles.body,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: ref.tr('addCommentHint'),
                          counterText: '',
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.send, size: 20, color: AppColors.primaryLight),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentTile extends ConsumerWidget {
  final CommentData comment;
  final bool canDelete;
  final VoidCallback onDelete;
  const _CommentTile({required this.comment, required this.canDelete, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live identity from users/{uid}; the comment's denormalized copy is
    // only the paint-first fallback.
    final author = identityOf(ref, comment.userId);
    final name = author?.nameToShow ?? comment.userName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(name: name, imageUrl: author?.userAvatar ?? comment.userAvatar, radius: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    if (comment.createdAt != null)
                      Text(Fmt.timeAgo(comment.createdAt!), style: AppTextStyles.captionMuted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.content, style: AppTextStyles.body.copyWith(fontSize: 13.5)),
              ],
            ),
          ),
          if (canDelete)
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 15, color: AppColors.textMuted),
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
