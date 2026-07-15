import 'user_model.dart';

enum MessageKind { text, aniVideo, system }

class MessageModel {
  final String id;
  final bool isMe;
  final String text;
  final MessageKind kind;
  final String videoTitle; // for aniVideo bubbles
  final String videoTag;
  final DateTime time;
  final bool read;

  const MessageModel({
    required this.id,
    required this.isMe,
    this.text = '',
    this.kind = MessageKind.text,
    this.videoTitle = '',
    this.videoTag = '',
    required this.time,
    this.read = true,
  });
}

class Conversation {
  final String id;
  final UserModel user;
  final String lastMessage;
  final DateTime lastTime;
  final int unread;
  final int streak;
  final List<MessageModel> messages;
  final bool streakAtRisk;

  /// Whether the friend is currently online (drives the green presence dot).
  final bool isOnline;

  const Conversation({
    required this.id,
    required this.user,
    required this.lastMessage,
    required this.lastTime,
    this.unread = 0,
    this.streak = 0,
    this.messages = const [],
    this.streakAtRisk = false,
    this.isOnline = false,
  });
}
