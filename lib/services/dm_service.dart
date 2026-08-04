import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/utils/post_image_compressor.dart';
import '../data/models/dm_conversation.dart';
import '../data/models/dm_message.dart';
import 'auth_service.dart';

/// One page of a thread's history, newest first. [cursor] is an opaque
/// continuation token — pass it back to [DmService.olderMessages] to fetch
/// the page before this one; null/absent [hasMore] means the thread is
/// exhausted.
class DmMessagePage {
  final List<DmMessage> messages;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
  const DmMessagePage({
    required this.messages,
    required this.cursor,
    required this.hasMore,
  });
}

/// 1:1 direct messages, backed by `conversations/{cid}` and its `messages`
/// subcollection.
///
/// Same operating contract as RoomService: singleton, every Firestore call
/// bounded by [writeTimeout]. With offline persistence on, a write against an
/// unreachable backend never throws — it queues locally and its Future only
/// completes on server ack — so an unbounded await would hang the UI. The
/// timeout surfaces the failure instead. It does NOT cancel the queued write:
/// a timed-out call may still commit once connectivity returns.
class DmService {
  DmService._();
  static final DmService instance = DmService._();

  static const Duration writeTimeout = Duration(seconds: 10);

  /// Image uploads move ~1 MB and deserve more headroom than a doc write —
  /// still bounded so the composer can never hang forever.
  static const Duration uploadTimeout = Duration(seconds: 30);

  /// Messages fetched per page (newest-first live window + older pages).
  static const int messagesPageSize = 30;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');
  CollectionReference<Map<String, dynamic>> _messages(String cid) =>
      _conversations.doc(cid).collection('messages');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[DmService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[DmService] $op failed: $e');
      rethrow;
    }
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  /// Every thread [uid] participates in, most recently active first. Backed
  /// by the composite index (participants CONTAINS, updatedAt DESC) in
  /// firestore.indexes.json.
  Stream<List<DmConversation>> watchConversations(String uid) => _conversations
      .where('participants', arrayContains: uid)
      .orderBy('updatedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(DmConversation.fromDoc).toList());

  /// One thread, live. Emits null if the doc doesn't exist (or access is
  /// lost). Drives the chat screen's app bar identity and blocked state.
  Stream<DmConversation?> watchConversation(String cid) => _conversations
      .doc(cid)
      .snapshots()
      .map((d) => d.exists ? DmConversation.fromDoc(d) : null);

  Query<Map<String, dynamic>> _newestFirst(String cid) =>
      _messages(cid).orderBy('createdAt', descending: true);

  /// Live window over the newest [messagesPageSize] messages. Local sends
  /// appear here immediately via latency compensation (pending=true until
  /// the server acks), which is what makes optimistic UI reconcile instead
  /// of duplicate — the send and its confirmation are the same doc.
  Stream<DmMessagePage> watchLatestMessages(String cid) =>
      _newestFirst(cid).limit(messagesPageSize).snapshots().map(_toPage);

  /// One page of history strictly older than [cursor] (bounded get — this
  /// is the load-more path; old messages don't change, so no listener).
  Future<DmMessagePage> olderMessages(
      String cid, DocumentSnapshot<Map<String, dynamic>> cursor) {
    return _guard('olderMessages($cid)', () async {
      final snap = await _newestFirst(cid)
          .startAfterDocument(cursor)
          .limit(messagesPageSize)
          .get()
          .timeout(writeTimeout);
      return _toPage(snap);
    });
  }

  DmMessagePage _toPage(QuerySnapshot<Map<String, dynamic>> snap) =>
      DmMessagePage(
        messages: snap.docs.map(DmMessage.fromDoc).toList(),
        cursor: snap.docs.isEmpty ? null : snap.docs.last,
        hasMore: snap.docs.length == messagesPageSize,
      );

  /// Messages [uid] hasn't read yet, counted server-side with a count()
  /// aggregation — deliberately NO stored unread counter to drift or forge;
  /// the per-uid lastReadAt mark on the conversation doc is the only state.
  /// A missing mark means the whole thread is unread.
  Future<int> unreadCount(String cid, String uid) {
    return _guard('unreadCount($cid)', () async {
      final convo = await _conversations.doc(cid).get().timeout(writeTimeout);
      if (!convo.exists) return 0;
      final lastRead =
          (convo.data()?['lastReadAt'] as Map<String, dynamic>?)?[uid];
      Query<Map<String, dynamic>> q =
          _messages(cid).where('senderId', isNotEqualTo: uid);
      if (lastRead is Timestamp) {
        q = q.where('createdAt', isGreaterThan: lastRead);
      }
      final agg = await q.count().get().timeout(writeTimeout);
      return agg.count ?? 0;
    });
  }

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Opens the thread between the signed-in user and [otherUid], returning
  /// its deterministic id ([DmConversation.cidFor]).
  ///
  /// Idempotent by way of the existence check: an existing doc is returned
  /// untouched — re-setting it would be an update touching createdAt, which
  /// no rules branch admits, so even a lost race cannot produce a second doc
  /// or clobber the first. The create goes through a WriteBatch so however
  /// late a timed-out-but-queued commit lands, it lands whole.
  Future<String> openConversation(String otherUid) {
    return _guard('openConversation($otherUid)', () async {
      final uid = await _uid();
      if (uid == otherUid) {
        throw ArgumentError('cannot open a conversation with yourself');
      }
      final cid = DmConversation.cidFor(uid, otherUid);
      final ref = _conversations.doc(cid);
      // Bounded get — don't rely on an unreachable backend happening to throw.
      if ((await ref.get().timeout(writeTimeout)).exists) return cid;
      final batch = _db.batch()
        ..set(
            ref,
            DmConversation(
              id: cid,
              participants: [uid, otherUid],
            ).toMap());
      await batch.commit().timeout(writeTimeout);
      return cid;
    });
  }

  /// Sends [text] to [cid]: the message doc and the parent's preview fields
  /// (lastMessage capped at 120 — rules enforce it, this just complies —
  /// lastSenderId, server-stamped updatedAt) go in ONE batch, so however
  /// late a timed-out-but-queued commit lands, it lands whole — a message
  /// can never appear without its thread bump or vice versa.
  Future<void> sendMessage(String cid, String text) {
    return _guard('sendMessage($cid)', () async {
      final uid = await _uid();
      final trimmed = text.trim();
      if (trimmed.isEmpty) return;
      final body = _clamp(trimmed, 1000);
      final preview = _clamp(body, 120);
      final msgRef = _messages(cid).doc();
      final batch = _db.batch()
        ..set(msgRef, DmMessage(id: msgRef.id, senderId: uid, text: body).toMap())
        ..update(_conversations.doc(cid), {
          'lastMessage': preview,
          'lastSenderId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      await batch.commit().timeout(writeTimeout);
    });
  }

  /// Threads the signed-in user has blocked — drives the settings Block
  /// List.
  ///
  /// Deliberately the SAME query as the inbox, filtered client-side. A
  /// server-side `where('blockedBy', arrayContains: uid)` is rejected: the
  /// read rule gates on `participants`, and Firestore evaluates a query
  /// against the rule rather than the documents it happens to return
  /// (rules are not filters), so it cannot prove a blockedBy-only query
  /// safe. The two clauses can't be combined either — one array-contains
  /// per query. Reusing the inbox query also means no extra index.
  Stream<List<DmConversation>> watchBlockedConversations(String uid) =>
      watchConversations(uid).map(
          (all) => all.where((c) => c.blockedBy.contains(uid)).toList());

  /// Toggles the caller's reaction on a message: same emoji again removes
  /// it, anything else sets it. The dot-path write touches only the
  /// caller's own reactions key — the only shape the rules branch admits.
  Future<void> toggleReaction(String cid, String messageId, String emoji) {
    return _guard('toggleReaction($cid/$messageId)', () async {
      final uid = await _uid();
      final ref = _messages(cid).doc(messageId);
      final current =
          ((await ref.get().timeout(writeTimeout)).data()?['reactions']
              as Map<String, dynamic>?)?[uid];
      await ref.update({
        'reactions.$uid': current == emoji ? FieldValue.delete() : emoji,
      }).timeout(writeTimeout);
    });
  }

  /// Adds/removes the signed-in user from [cid]'s blockedBy. arrayUnion /
  /// arrayRemove produce exactly the add-or-remove-self diff the rules
  /// branch admits, with no read-modify-write race.
  Future<void> setBlocked(String cid, bool blocked) {
    return _guard('setBlocked($cid, $blocked)', () async {
      final uid = await _uid();
      await _conversations.doc(cid).update({
        'blockedBy': blocked
            ? FieldValue.arrayUnion([uid])
            : FieldValue.arrayRemove([uid]),
      }).timeout(writeTimeout);
    });
  }

  /// Reports the counterpart of [cid]. Same write-only reports/ sink the
  /// post/video/news reports use — reviewed server-side, never readable
  /// from clients.
  Future<void> reportUser(String cid, String reportedUid, String reason) {
    return _guard('reportUser($cid)', () async {
      final uid = await _uid();
      await _db.collection('reports').add({
        'reportedUid': reportedUid,
        'cid': cid,
        'reason': reason,
        'reporterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(writeTimeout);
    });
  }

  /// Reports one message — the user-shaped report plus the offending
  /// messageId so review can pull the exact doc.
  Future<void> reportMessage(
      String cid, String messageId, String reportedUid, String reason) {
    return _guard('reportMessage($cid/$messageId)', () async {
      final uid = await _uid();
      await _db.collection('reports').add({
        'reportedUid': reportedUid,
        'cid': cid,
        'messageId': messageId,
        'reason': reason,
        'reporterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(writeTimeout);
    });
  }

  /// Sends the image at [imagePath] (with an optional [caption]) to [cid]:
  /// compress to a JPEG the `dm_images/` Storage rule is guaranteed to
  /// accept (same contract as posts/stories), upload FIRST, then commit the
  /// message + preview bump in the same one batch as a text send.
  ///
  /// If the batch fails after the upload succeeded, the blob is orphaned —
  /// deliberately left alone (client deletes are denied by rules, and a
  /// cleanup path invites worse bugs than a stray file); _guard logs it.
  Future<void> sendImageMessage(String cid, String imagePath,
      {String caption = ''}) {
    return _guard('sendImageMessage($cid)', () async {
      final uid = await _uid();
      final jpeg = await PostImageCompressor.compress(imagePath);
      final msgRef = _messages(cid).doc();
      final blob =
          FirebaseStorage.instance.ref('dm_images/$cid/${msgRef.id}.jpg');
      await blob
          .putData(jpeg, SettableMetadata(contentType: 'image/jpeg'))
          .timeout(uploadTimeout);
      final url = await blob.getDownloadURL().timeout(writeTimeout);

      final text = _clamp(caption.trim(), 1000);
      final preview = text.isNotEmpty ? _clamp(text, 120) : '📷 Photo';
      final batch = _db.batch()
        ..set(
            msgRef,
            DmMessage(id: msgRef.id, senderId: uid, text: text, imageUrl: url)
                .toMap())
        ..update(_conversations.doc(cid), {
          'lastMessage': preview,
          'lastSenderId': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      await batch.commit().timeout(writeTimeout);
    });
  }

  /// [s] cut to at most [max] UTF-16 units without splitting a surrogate
  /// pair — a dangling half-emoji is not valid UTF-8 and can't be stored.
  static String _clamp(String s, int max) {
    if (s.length <= max) return s;
    var end = max;
    if ((s.codeUnitAt(end - 1) & 0xFC00) == 0xD800) end--;
    return s.substring(0, end);
  }

  /// Stamps [uid]'s read mark to now. The dot-path update touches only the
  /// caller's own lastReadAt key — the only shape the read-receipt rules
  /// branch admits.
  Future<void> markRead(String cid, String uid) {
    return _guard('markRead($cid)', () async {
      await _conversations
          .doc(cid)
          .update({'lastReadAt.$uid': FieldValue.serverTimestamp()})
          .timeout(writeTimeout);
    });
  }
}
