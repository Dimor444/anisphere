import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/dm_conversation.dart';
import 'auth_service.dart';

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
