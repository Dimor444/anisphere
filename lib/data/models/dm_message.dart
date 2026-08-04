import 'package:cloud_firestore/cloud_firestore.dart';

/// One direct message, stored at `conversations/{cid}/messages/{mid}`.
///
/// Carries [senderId], never an isMe flag — viewer-relative logic belongs in
/// the widget layer, not the model. No sender name/avatar/verified fields
/// either: identity resolves at render time through identityProvider.
///
/// Deliberately NOT the mock [MessageModel] in message_model.dart.
class DmMessage {
  final String id;
  final String senderId;
  final String text;

  /// Optional image attachment URL (Phase 3 wires uploads; the field shape
  /// is fixed now so rules and docs don't churn).
  final String? imageUrl;
  final DateTime? createdAt;

  /// True while this doc is a local write awaiting server ack (latency
  /// compensation) — drives the send-pending indicator. Derived from
  /// snapshot metadata, never stored.
  final bool pending;

  /// Per-uid reaction emoji ({uid: emoji}, one per participant). Written
  /// only through the own-key update branch — never part of the create
  /// payload, so [toMap] deliberately omits it.
  final Map<String, String> reactions;

  const DmMessage({
    required this.id,
    required this.senderId,
    this.text = '',
    this.imageUrl,
    this.createdAt,
    this.pending = false,
    this.reactions = const {},
  });

  factory DmMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawReactions = d['reactions'] as Map<String, dynamic>? ?? const {};
    return DmMessage(
      id: doc.id,
      senderId: d['senderId'] as String? ?? '',
      text: d['text'] as String? ?? '',
      imageUrl: d['imageUrl'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      pending: doc.metadata.hasPendingWrites,
      reactions: {
        for (final e in rawReactions.entries)
          if (e.value is String) e.key: e.value as String,
      },
    );
  }

  /// The create payload. createdAt is server-stamped (rules require
  /// `== request.time`); imageUrl is omitted rather than written as null so
  /// the rules' `hasOnly` whitelist admits it only when actually present.
  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
