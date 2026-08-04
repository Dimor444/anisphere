import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/dm_conversation.dart';
import '../../data/models/dm_message.dart';
import '../../services/auth_service.dart';
import '../../services/dm_service.dart';
import '../../shared/providers/identity_provider.dart';
import '../../shared/providers/language_provider.dart';
import '../../shared/widgets/user_avatar.dart';
import '../../shared/widgets/verified_badge.dart';

/// The only reactions offered — a fixed row, deliberately no picker.
const _reactionEmojis = ['❤️', '😂', '😮', '😢', '🔥', '👍'];

/// One DM thread at `/chat/:cid`, fully Firestore-backed.
///
/// Bubble side is decided by senderId == the signed-in uid — never a stored
/// isMe. The newest [DmService.messagesPageSize] messages ride a live
/// listener; older history loads in pages on scroll. Every message ever seen
/// is kept in an id-keyed map, so the sliding live window can't open gaps
/// and a local pending send reconciles (same doc id) instead of duplicating.
class ChatScreen extends ConsumerStatefulWidget {
  final String cid;
  const ChatScreen({super.key, required this.cid});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  String? _me;
  DmConversation? _convo;
  bool _convoLoaded = false;

  StreamSubscription<DmConversation?>? _convoSub;
  StreamSubscription<DmMessagePage>? _liveSub;
  bool _liveLoaded = false;

  /// Every message seen this session, keyed by doc id (see class doc).
  final Map<String, DmMessage> _byId = {};

  /// Local arrival stamp per id — orders docs whose serverTimestamp hasn't
  /// resolved yet (pending sends read createdAt == null).
  final Map<String, DateTime> _seen = {};

  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _cursorSeeded = false;
  bool _hasMore = false;
  bool _loadingMore = false;

  String? _lastMarkedMsgId;

  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// True from pick through upload — compression and the blob upload happen
  /// BEFORE the batch write, so latency compensation can't show a pending
  /// bubble yet; the composer spinner covers that window.
  bool _sendingImage = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _init();
  }

  Future<void> _init() async {
    final uid = (await AuthService.instance.initAuth()).uid;
    if (!mounted) return;
    setState(() => _me = uid);

    _convoSub = DmService.instance.watchConversation(widget.cid).listen((c) {
      if (!mounted) return;
      setState(() {
        _convo = c;
        _convoLoaded = true;
      });
    });

    _liveSub = DmService.instance.watchLatestMessages(widget.cid).listen((page) {
      if (!mounted) return;
      setState(() {
        _merge(page.messages);
        _liveLoaded = true;
        // The pagination anchor comes from the FIRST live window only —
        // afterwards olderMessages owns the cursor as it walks back.
        if (!_cursorSeeded) {
          _cursorSeeded = true;
          _cursor = page.cursor;
          _hasMore = page.hasMore;
        }
      });
      _maybeMarkRead(page);
    });

    // Opening the thread reads it.
    DmService.instance.markRead(widget.cid, uid).catchError((Object _) {});
  }

  void _merge(Iterable<DmMessage> msgs) {
    for (final m in msgs) {
      _byId[m.id] = m;
      _seen.putIfAbsent(m.id, DateTime.now);
    }
  }

  /// Newest-first for the reverse ListView.
  List<DmMessage> get _ordered {
    final list = _byId.values.toList()
      ..sort((a, b) {
        final ta = a.createdAt ?? _seen[a.id]!;
        final tb = b.createdAt ?? _seen[b.id]!;
        final byTime = tb.compareTo(ta);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return list;
  }

  /// New incoming message while this screen is up and the app is foreground
  /// — mark it read so the list dot clears live.
  void _maybeMarkRead(DmMessagePage page) {
    final me = _me;
    if (me == null || page.messages.isEmpty) return;
    final newest = page.messages.first;
    if (newest.senderId == me || newest.id == _lastMarkedMsgId) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _lastMarkedMsgId = newest.id;
    DmService.instance.markRead(widget.cid, me).catchError((Object _) {});
  }

  void _maybeLoadMore() {
    if (!_hasMore || _loadingMore || _cursor == null) return;
    // reverse:true — maxScrollExtent is the oldest end.
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 300) {
      return;
    }
    _loadOlder();
  }

  Future<void> _loadOlder() async {
    final cursor = _cursor;
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await DmService.instance.olderMessages(widget.cid, cursor);
      if (!mounted) return;
      setState(() {
        _merge(page.messages);
        _cursor = page.cursor ?? _cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // Scrolling again retries; history is not worth an error banner.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || (_convo?.isBlocked ?? false)) return;
    Haptics.light();
    _input.clear();
    try {
      await DmService.instance.sendMessage(widget.cid, text);
    } on TimeoutException {
      if (!mounted) return;
      // The queued write may still land later — the bubble stays pending.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Still sending — it will go out once you're back online."),
        duration: Duration(seconds: 3),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't send that message."),
        duration: Duration(seconds: 2),
      ));
    }
  }

  /// Pick → compress → upload → batched send. The composer text rides along
  /// as the caption and is cleared optimistically like a text send.
  Future<void> _sendImage() async {
    if (_sendingImage || (_convo?.isBlocked ?? false)) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    Haptics.light();
    final caption = _input.text.trim();
    _input.clear();
    setState(() => _sendingImage = true);
    try {
      await DmService.instance.sendImageMessage(widget.cid, picked.path, caption: caption);
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Still sending — it will go out once you're back online."),
        duration: Duration(seconds: 3),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't send that photo."),
        duration: Duration(seconds: 2),
      ));
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  /// Block or unblock the counterpart. Writes only the caller's own entry
  /// in blockedBy, so either side can block and only the blocker can lift
  /// their own block — while ANY entry stands, both composers are frozen.
  Future<void> _toggleBlock() async {
    final convo = _convo;
    final me = _me;
    if (convo == null || me == null) return;
    final blocking = !convo.blockedBy.contains(me);
    Haptics.medium();
    try {
      await DmService.instance.setBlocked(widget.cid, blocking);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(blocking ? 'Conversation blocked' : 'Conversation unblocked'),
        duration: const Duration(seconds: 2),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ref.tr('actionFailed')),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  /// Reason sheet shared by the user- and message-level reports; [onPick]
  /// receives the reason code. [titleKey] names what is being reported —
  /// the post-specific `whyReport` belongs to the feed, not here. The reason
  /// options themselves are shared with post reports.
  void _showReasonSheet(String titleKey, void Function(String code) onPick) {
    final reasons = [
      ('spam', ref.tr('reportSpam')),
      ('spoiler', ref.tr('reportSpoiler')),
      ('abuse', ref.tr('reportAbuse')),
      ('other', ref.tr('reportOther')),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(ref.tr(titleKey), style: AppTextStyles.subheading),
            const SizedBox(height: 6),
            for (final (code, label) in reasons)
              ListTile(
                title: Text(label, style: AppTextStyles.body),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  onPick(code);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  /// Fire a report and acknowledge it. The sink is write-only: a reporter
  /// can never read back what they (or anyone) filed.
  Future<void> _submitReport(Future<void> Function() send) async {
    final messenger = ScaffoldMessenger.of(context);
    final thanks = ref.tr('postReported');
    final failed = ref.tr('actionFailed');
    try {
      await send();
      messenger.showSnackBar(SnackBar(content: Text(thanks)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  void _reportUser() {
    final me = _me;
    final other = _convo?.otherUid(me ?? '') ?? '';
    if (other.isEmpty) return;
    _showReasonSheet('whyReportUser',
        (code) => _submitReport(() => DmService.instance.reportUser(widget.cid, other, code)));
  }

  /// Long-press on a bubble: the fixed reaction row, plus reporting for
  /// the counterpart's messages. Reactions are frozen while blocked.
  void _showMessageActions(DmMessage message) {
    final me = _me;
    if (me == null) return;
    final blocked = _convo?.isBlocked ?? false;
    final mine = message.senderId == me;
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            if (blocked)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Text('Reactions are unavailable while this conversation is blocked.',
                    textAlign: TextAlign.center, style: AppTextStyles.captionMuted),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in _reactionEmojis)
                    _ReactionButton(
                      emoji: emoji,
                      selected: message.reactions[me] == emoji,
                      onTap: () {
                        Navigator.pop(sheetCtx);
                        Haptics.light();
                        // Same emoji again removes it — the service reads
                        // the current value and deletes on a match.
                        DmService.instance
                            .toggleReaction(widget.cid, message.id, emoji)
                            .catchError((Object _) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ref.tr('actionFailed')),
                            duration: const Duration(seconds: 2),
                          ));
                        });
                      },
                    ),
                ],
              ),
            if (!mine) ...[
              const Divider(height: 22),
              ListTile(
                leading: const Icon(LucideIcons.flag, size: 18, color: AppColors.error),
                title: Text('Report message',
                    style: AppTextStyles.body.copyWith(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showReasonSheet(
                      'whyReportMessage',
                      (code) => _submitReport(() => DmService.instance
                          .reportMessage(widget.cid, message.id, message.senderId, code)));
                },
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _convoSub?.cancel();
    _liveSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final otherUid = (me == null) ? '' : (_convo?.otherUid(me) ?? '');
    final other = otherUid.isEmpty ? null : identityOf(ref, otherUid);
    final name = other?.nameToShow ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          UserAvatar(name: name.isEmpty ? '?' : name, imageUrl: other?.userAvatar, radius: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(name.isEmpty ? 'Anime fan' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.subheading),
                ),
                if (other?.isVerified == true) ...[
                  const SizedBox(width: 4),
                  const VerifiedBadge(size: BadgeSize.sm),
                ],
              ]),
              if (other != null) Text('@${other.userName}', style: AppTextStyles.captionMuted),
            ]),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsis, size: 20),
            color: AppColors.surface,
            onSelected: (v) => v == 'block' ? _toggleBlock() : _reportUser(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  const Icon(LucideIcons.ban, size: 17, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    (me != null && (_convo?.blockedBy.contains(me) ?? false)) ? 'Unblock' : 'Block',
                    style: AppTextStyles.body,
                  ),
                ]),
              ),
              PopupMenuItem(
                value: 'report',
                child: Row(children: [
                  const Icon(LucideIcons.flag, size: 17, color: AppColors.error),
                  const SizedBox(width: 10),
                  Text('Report user', style: AppTextStyles.body.copyWith(color: AppColors.error)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _body(me),
    );
  }

  Widget _body(String? me) {
    if (me == null || (!_convoLoaded && !_liveLoaded)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_convoLoaded && _convo == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('This conversation is unavailable.',
              textAlign: TextAlign.center, style: AppTextStyles.bodyMuted),
        ),
      );
    }
    final messages = _ordered;
    final blocked = _convo?.isBlocked ?? false;

    return Column(children: [
      Expanded(
        child: messages.isEmpty
            ? const Center(child: Text('Say hi 👋', style: AppTextStyles.bodyMuted))
            : ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.all(14),
                itemCount: messages.length + (_loadingMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == messages.length) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    );
                  }
                  return _Bubble(
                    message: messages[i],
                    isMine: messages[i].senderId == me,
                    // Read state derives from the counterpart's read mark —
                    // no per-message field exists or is needed.
                    otherLastRead: _convo?.lastReadBy(_convo!.otherUid(me)),
                    myUid: me,
                    onLongPress: () => _showMessageActions(messages[i]),
                  );
                },
              ),
      ),
      if (blocked) const _BlockedBanner() else _composer(),
    ]);
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(children: [
          IconButton(
            onPressed: _sendingImage ? null : _sendImage,
            icon: _sendingImage
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.image, size: 22, color: AppColors.textSecondary),
          ),
          Expanded(
            child: TextField(
              controller: _input,
              style: AppTextStyles.body,
              maxLength: 1000,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _send(),
              decoration:
                  const InputDecoration(hintText: 'Message…', isDense: true, counterText: ''),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle),
              child: const Icon(LucideIcons.send, color: Colors.white, size: 19),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One message bubble. Side and styling come from [isMine] (senderId
/// comparison in the caller) — the model itself is viewer-neutral.
/// [otherLastRead] is the counterpart's read mark: own messages older than
/// it show the double (read) tick, newer ones the single (sent) tick.
class _Bubble extends StatelessWidget {
  final DmMessage message;
  final bool isMine;
  final DateTime? otherLastRead;
  final String myUid;
  final VoidCallback onLongPress;
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.otherLastRead,
    required this.myUid,
    required this.onLongPress,
  });

  bool get _read =>
      otherLastRead != null &&
      message.createdAt != null &&
      !message.createdAt!.isAfter(otherLastRead!);

  @override
  Widget build(BuildContext context) {
    final hasImage = message.imageUrl != null;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: message.pending ? 0.65 : 1,
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding: hasImage
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isMine ? AppGradients.brand : null,
                    color: isMine ? null : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: isMine ? null : Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasImage)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.network(
                            message.imageUrl!,
                            width: 220,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) => progress == null
                                ? child
                                : Container(
                                    width: 220,
                                    height: 160,
                                    color: Colors.black26,
                                    child: const Center(
                                      child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2)),
                                    ),
                                  ),
                            errorBuilder: (_, __, ___) => Container(
                              width: 220,
                              height: 120,
                              color: Colors.black26,
                              child: const Icon(LucideIcons.imageOff,
                                  size: 26, color: AppColors.textMuted),
                            ),
                          ),
                        ),
                      if (message.text.isNotEmpty)
                        Padding(
                          padding:
                              hasImage ? const EdgeInsets.fromLTRB(10, 8, 10, 6) : EdgeInsets.zero,
                          child: Text(message.text,
                              style: AppTextStyles.body.copyWith(color: Colors.white)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (message.reactions.isNotEmpty)
              _ReactionChips(
                reactions: message.reactions,
                myUid: myUid,
                onTap: onLongPress,
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: message.pending
                  ? const _PendingDots()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_time(message.createdAt),
                            style: AppTextStyles.captionMuted.copyWith(fontSize: 10)),
                        // Own messages only: single tick = sent (server-acked),
                        // double = read. No delivered state — unobservable.
                        if (isMine) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _read ? LucideIcons.checkCheck : LucideIcons.check,
                            size: 12,
                            color: _read ? AppColors.accent : AppColors.textMuted,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime? t) => t == null
      ? ''
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// One emoji in the long-press reaction row; [selected] marks the caller's
/// current reaction, so tapping it again reads as "remove".
class _ReactionButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _ReactionButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.22) : Colors.transparent,
          shape: BoxShape.circle,
          border: selected ? Border.all(color: AppColors.primary) : null,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

/// Reactions rendered inline under a bubble — one chip per distinct emoji
/// with its count (max two reactors in a 1:1 thread). The caller's own
/// reaction is outlined. Tapping reopens the same row that set it.
class _ReactionChips extends StatelessWidget {
  final Map<String, String> reactions;
  final String myUid;
  final VoidCallback onTap;
  const _ReactionChips({
    required this.reactions,
    required this.myUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final mine = reactions[myUid];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in counts.entries)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: entry.key == mine ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(entry.key, style: const TextStyle(fontSize: 12)),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 3),
                    Text('${entry.value}',
                        style: AppTextStyles.captionMuted.copyWith(fontSize: 10)),
                  ],
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Send-pending indicator — the old typing-bubble dots, shrunk to timestamp
/// scale. Visuals only; there is deliberately no typing presence here.
class _PendingDots extends StatelessWidget {
  const _PendingDots();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 5,
          height: 5,
          decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .fadeIn(delay: (i * 180).ms, duration: 400.ms)
            .scaleXY(begin: 0.6, end: 1, duration: 400.ms);
      }),
    );
  }
}

/// Shown in place of the composer while blockedBy is non-empty — both
/// participants see it; rules deny sends from both sides regardless.
class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(LucideIcons.ban, size: 18, color: AppColors.textMuted),
          const SizedBox(height: 6),
          Text('This conversation is blocked',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Text("Messages can't be sent or received right now.",
              style: AppTextStyles.captionMuted),
        ]),
      ),
    );
  }
}
