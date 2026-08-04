import 'package:cloud_firestore/cloud_firestore.dart';

/// A 1:1 direct-message thread, stored at `conversations/{cid}`.
///
/// The doc id is deterministic — [cidFor] joins the two sorted uids — so the
/// same pair always maps to the same doc and "open" is naturally idempotent.
///
/// No author identity is denormalized here (no names, avatars, or verified
/// flags): the counterpart's identity resolves at render time through
/// identityProvider, exactly like posts and comments.
///
/// Deliberately NOT the mock [Conversation] in message_model.dart — that model
/// is viewer-relative demo data and must never be serialized.
class DmConversation {
  final String id;

  /// Exactly two uids, stored sorted (matching [cidFor]'s order).
  final List<String> participants;
  final DateTime? createdAt;

  /// Bumped on every send — the conversation list orders by this.
  final DateTime? updatedAt;

  /// Preview of the newest message ('' until the first send).
  final String lastMessage;
  final String lastSenderId;

  /// Per-uid read high-water marks. Rules only ever admit a participant
  /// moving their OWN key, so unread state cannot be forged for others.
  final Map<String, DateTime> lastReadAt;

  /// Participants who blocked this thread. Any non-empty value freezes
  /// message creates for BOTH sides (enforced by rules).
  final List<String> blockedBy;

  const DmConversation({
    required this.id,
    required this.participants,
    this.createdAt,
    this.updatedAt,
    this.lastMessage = '',
    this.lastSenderId = '',
    this.lastReadAt = const {},
    this.blockedBy = const [],
  });

  /// Deterministic conversation id for a pair of uids, order-independent.
  static String cidFor(String a, String b) => ([a, b]..sort()).join('_');

  /// The counterpart of [me], or '' when [me] isn't a participant.
  String otherUid(String me) =>
      participants.firstWhere((p) => p != me, orElse: () => '');

  bool get isBlocked => blockedBy.isNotEmpty;

  DateTime? lastReadBy(String uid) => lastReadAt[uid];

  factory DmConversation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawRead = d['lastReadAt'] as Map<String, dynamic>? ?? const {};
    return DmConversation(
      id: doc.id,
      participants:
          (d['participants'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      lastMessage: d['lastMessage'] as String? ?? '',
      lastSenderId: d['lastSenderId'] as String? ?? '',
      lastReadAt: {
        for (final e in rawRead.entries)
          if (e.value is Timestamp) e.key: (e.value as Timestamp).toDate(),
      },
      blockedBy:
          (d['blockedBy'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// The create payload. Timestamps are server-stamped (rules require
  /// `== request.time`), message state starts zeroed, and lastReadAt starts
  /// empty — a missing key reads as "everything unread", which is correct for
  /// a brand-new thread.
  Map<String, dynamic> toMap() => {
        'participants': [...participants]..sort(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': lastMessage,
        'lastSenderId': lastSenderId,
        'lastReadAt': <String, dynamic>{},
        'blockedBy': <String>[],
      };
}
