import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_gradients.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/haptics.dart';
import '../../data/models/message_model.dart';
import '../../data/sample_data.dart';
import '../../shared/widgets/anime_cover_image.dart';
import '../../shared/widgets/user_avatar.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late Conversation _convo;
  late List<MessageModel> _messages;
  final _input = TextEditingController();
  bool _typing = true;

  @override
  void initState() {
    super.initState();
    _convo = SampleData.conversations.firstWhere((c) => c.id == widget.conversationId, orElse: () => SampleData.conversations.first);
    _messages = List.of(_convo.messages.reversed); // reverse:true list
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _typing = false);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send([MessageModel? custom]) {
    final msg = custom ?? MessageModel(id: 'n${_messages.length}', isMe: true, text: _input.text.trim(), time: DateTime.now());
    if (custom == null && msg.text.isEmpty) return;
    Haptics.light();
    setState(() {
      _messages.insert(0, msg);
      _input.clear();
    });
  }

  /// Outgoing call. Awaits the call duration (seconds) the screen pops with,
  /// then drops a "Call ended" system message into the chat.
  Future<void> _startCall({required bool video}) async {
    Haptics.medium();
    final seconds = await Navigator.of(context).push<int>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CallScreen(user: _convo.user, video: video),
    ));
    _logCall(seconds, video);
  }

  /// Simulates an *incoming* call (demo trigger: long-press a header call icon).
  Future<void> _simulateIncoming({required bool video}) async {
    Haptics.medium();
    final seconds = await Navigator.of(context).push<int>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => IncomingCallScreen(user: _convo.user, video: video),
    ));
    _logCall(seconds, video);
  }

  /// Inserts a system-type message summarising a finished call.
  void _logCall(int? seconds, bool video) {
    if (!mounted || seconds == null) return; // null = dismissed before answering
    final icon = video ? '📹' : '📞';
    final label = seconds > 0 ? '$icon Call ended · ${_duration(seconds)}' : '$icon Call cancelled';
    setState(() {
      _messages.insert(0, MessageModel(id: 'call${_messages.length}', isMe: false, kind: MessageKind.system, text: label, time: DateTime.now()));
    });
  }

  String _duration(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  void _shareAniVideo() {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share an Ani Video', style: AppTextStyles.heading),
              const SizedBox(height: 14),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 6,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final a = SampleData.animeList[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _send(MessageModel(id: 'v${_messages.length}', isMe: true, kind: MessageKind.aniVideo, videoTitle: '${a.title} • AMV', videoTag: a.title, time: DateTime.now()));
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 100,
                          child: Stack(
                            fit: StackFit.expand,
                            alignment: Alignment.center,
                            children: [
                              AnimeCoverImage(animeName: a.title, gradient: a.gradient, emoji: a.emoji, emojiSize: 40),
                              const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 30)),
                              Positioned(bottom: 6, left: 6, right: 6, child: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          UserAvatar.fromUser(_convo.user, radius: 17, isOnline: _convo.isOnline),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_convo.user.username, style: AppTextStyles.subheading),
            if (_convo.isOnline)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('Online', style: AppTextStyles.captionMuted.copyWith(color: AppColors.success)),
              ])
            else if (_convo.streak > 0)
              Text('🔥 ${_convo.streak}-day streak', style: AppTextStyles.captionMuted),
          ]),
        ]),
        // Tap = outgoing call. Long-press = simulate an incoming call (demo).
        actions: [
          GestureDetector(
            onLongPress: () => _simulateIncoming(video: false),
            child: IconButton(icon: const Icon(LucideIcons.phone, size: 18), onPressed: () => _startCall(video: false)),
          ),
          GestureDetector(
            onLongPress: () => _simulateIncoming(video: true),
            child: IconButton(icon: const Icon(LucideIcons.video, size: 18), onPressed: () => _startCall(video: true)),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_convo.streakAtRisk)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.streak.withOpacity(0.15),
              child: Row(children: [
                const Icon(LucideIcons.flame, color: AppColors.streak, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Your ${_convo.streak}-day streak ends in 4h! Send a message to keep it alive.', style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary))),
              ]),
            ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (_, i) {
                if (_typing && i == 0) return const _TypingBubble();
                final m = _messages[_typing ? i - 1 : i];
                return _bubble(m);
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _bubble(MessageModel m) {
    // System messages (e.g. "Call ended · 00:12") render as a centered pill.
    if (m.kind == MessageKind.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
          child: Text(m.text, style: AppTextStyles.captionMuted),
        ),
      );
    }
    final isVideo = m.kind == MessageKind.aniVideo;
    return Align(
      alignment: m.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          crossAxisAlignment: m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (isVideo)
              Container(
                width: 220,
                decoration: BoxDecoration(gradient: AppGradients.forSeed(m.videoTag), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 120,
                      child: Stack(alignment: Alignment.center, children: [
                        Text(SampleData.animeByTitle(m.videoTag).emoji, style: const TextStyle(fontSize: 50)),
                        Container(width: 44, height: 44, decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30)),
                      ]),
                    ),
                    Padding(padding: const EdgeInsets.all(10), child: Row(children: [const Icon(LucideIcons.playCircle, size: 14, color: Colors.white), const SizedBox(width: 6), Expanded(child: Text(m.videoTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))])),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: m.isMe ? AppGradients.brand : null,
                  color: m.isMe ? null : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: m.isMe ? null : Border.all(color: AppColors.border),
                ),
                child: Text(m.text, style: AppTextStyles.body.copyWith(color: Colors.white)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!m.isMe)
                    GestureDetector(
                      onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🌐 Translated'), duration: Duration(seconds: 1))),
                      child: const Padding(padding: EdgeInsets.only(right: 6), child: Icon(LucideIcons.languages, size: 12, color: AppColors.accent)),
                    ),
                  Text(_time(m.time), style: AppTextStyles.captionMuted.copyWith(fontSize: 10)),
                  if (m.isMe) ...[const SizedBox(width: 4), Icon(m.read ? LucideIcons.checkCheck : LucideIcons.check, size: 12, color: m.read ? AppColors.accent : AppColors.textMuted)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            IconButton(icon: const Icon(LucideIcons.smile, size: 22, color: AppColors.textSecondary), onPressed: () {}),
            IconButton(icon: const Icon(LucideIcons.paperclip, size: 20, color: AppColors.textSecondary), onPressed: () {}),
            GestureDetector(onTap: _shareAniVideo, child: const Text('🎬', style: TextStyle(fontSize: 22))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _input, style: AppTextStyles.body, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message…', isDense: true))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _send(),
              child: Container(width: 44, height: 44, decoration: const BoxDecoration(gradient: AppGradients.brand, shape: BoxShape.circle), child: const Icon(LucideIcons.send, color: Colors.white, size: 19)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: AppColors.textMuted, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(delay: (i * 180).ms, duration: 400.ms).scaleXY(begin: 0.6, end: 1, duration: 400.ms);
          }),
        ),
      ),
    );
  }
}
