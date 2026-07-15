import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/post.dart';
import '../../services/auth_service.dart';
import '../../services/feed_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/post_card.dart';
import '../../shared/widgets/user_avatar.dart';

/// Full post + live comments, with a composer pinned at the bottom.
class PostDetailScreen extends ConsumerStatefulWidget {
  final String postId;

  /// Snapshot passed from the feed so the card paints before the live doc
  /// arrives; the [FeedService.watchPost] stream takes over immediately.
  final PostData? initial;
  const PostDetailScreen({super.key, required this.postId, this.initial});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  static const int _commentsPage = 30;

  final _commentCtrl = TextEditingController();
  int _commentLimit = _commentsPage;
  bool _sending = false;

  String get _uid => AuthService.instance.uid ?? '';

  @override
  void initState() {
    super.initState();
    FeedService.instance.incrementViewCount(widget.postId);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    Haptics.light();
    setState(() => _sending = true);
    try {
      await FeedService.instance.addComment(widget.postId, text);
      if (!mounted) return;
      _commentCtrl.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.tr('actionFailed')),
        action: SnackBarAction(label: ref.tr('retry'), onPressed: _sendComment),
      ));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(CommentData c) async {
    try {
      await FeedService.instance.deleteComment(widget.postId, c.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.tr('actionFailed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('comments'))),
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppGradients.pageBg),
        child: StreamBuilder<PostData?>(
          stream: FeedService.instance.watchPost(widget.postId),
          initialData: widget.initial,
          builder: (context, postSnap) {
            final post = postSnap.data;
            if (post == null) {
              if (postSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return Center(child: Text(ref.tr('postDeleted'), style: AppTextStyles.captionMuted));
            }
            return Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<CommentData>>(
                    stream: FeedService.instance.getComments(widget.postId, limit: _commentLimit),
                    builder: (context, commentSnap) {
                      final comments = _sortedComments(commentSnap.data);
                      return ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        children: [
                          PostCard(post: post, expandable: false),
                          const SizedBox(height: 6),
                          if (comments == null)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          else if (comments.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Center(
                                child: Text(ref.tr('noCommentsYet'), style: AppTextStyles.captionMuted),
                              ),
                            )
                          else ...[
                            ...comments.map((c) => _CommentTile(
                                  comment: c,
                                  canDelete: c.userId == _uid || post.userId == _uid,
                                  onDelete: () => _deleteComment(c),
                                )),
                            // More to load when the page came back full.
                            if (comments.length >= _commentLimit)
                              TextButton(
                                onPressed: () => setState(() => _commentLimit += _commentsPage),
                                child: Text(ref.tr('comments'),
                                    style: const TextStyle(color: AppColors.primaryLight)),
                              ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                _composer(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Pending server timestamps (null createdAt) go on top — they're ours,
  /// written a moment ago.
  List<CommentData>? _sortedComments(List<CommentData>? comments) {
    if (comments == null) return null;
    final list = [...comments];
    list.sort((a, b) {
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return list;
  }

  Widget _composer() {
    final me = myIdentity(ref);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            UserAvatar(name: me?.nameToShow ?? '', imageUrl: me?.userAvatar, radius: 16),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                maxLength: CommentData.maxContentLength,
                style: AppTextStyles.body,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComment(),
                decoration: InputDecoration(
                  hintText: ref.tr('addCommentHint'),
                  counterText: '',
                  isDense: true,
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              onPressed: _sending ? null : _sendComment,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.send, size: 20, color: AppColors.primaryLight),
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
