import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/room.dart';
import 'auth_service.dart';

/// Community rooms backed by the `rooms` collection.
///
/// Watch Party only for now — synchronized playback is v2, so a room is just
/// a titled place with a live membership roster.
///
/// Membership is a self-keyed doc at `rooms/{roomId}/members/{uid}`; writing
/// it is the ONLY way memberCount moves, via the Cloud Function trigger in
/// functions/index.js. Nothing here ever writes memberCount — rules deny it.
class RoomService {
  RoomService._();
  static final RoomService instance = RoomService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _rooms => _db.collection('rooms');
  CollectionReference<Map<String, dynamic>> _members(String roomId) =>
      _rooms.doc(roomId).collection('members');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[RoomService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[RoomService] $op failed: $e');
      rethrow;
    }
  }

  // ── Reads ──────────────────────────────────────────────────────────────

  /// Live Watch Party rooms — live ones first, then newest. Backed by the
  /// composite index (type, isLive DESC, createdAt DESC) in
  /// firestore.indexes.json.
  Stream<List<Room>> watchPartyRooms({int limit = 50}) => _rooms
      .where('type', isEqualTo: Room.typeWatchParty)
      .orderBy('isLive', descending: true)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Room.fromDoc).toList());

  /// One room, live. Emits null if it is deleted out from under the viewer.
  Stream<Room?> roomById(String roomId) =>
      _rooms.doc(roomId).snapshots().map((d) => d.exists ? Room.fromDoc(d) : null);

  /// Live member count for [roomId], straight off the server-owned counter.
  Stream<int> memberCount(String roomId) =>
      roomById(roomId).map((r) => r?.memberCount ?? 0);

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Creates a Watch Party room and joins the creator to it, returning the new
  /// room id. The join is what sets memberCount to 1 — the trigger sees the
  /// members doc appear and bumps the parent.
  Future<String> createWatchParty({
    required String title,
    String? animeId,
    int? episodeNumber,
  }) {
    return _guard('createWatchParty', () async {
      final uid = await _uid();
      final room = Room(
        id: '',
        title: title.trim(),
        animeId: animeId,
        episodeNumber: episodeNumber,
        hostUid: uid,
        isLive: true,
      );
      final ref = await _rooms.add(room.toCreateMap());
      await joinRoom(ref.id);
      return ref.id;
    });
  }

  /// Adds the signed-in user to [roomId]'s roster.
  ///
  /// Idempotent by way of the existence check: rules allow create-and-delete
  /// but not update on a member doc, so re-writing an existing membership
  /// would be denied outright. Skipping it also keeps the trigger from seeing
  /// a second create and double-bumping memberCount. A lost race just means
  /// the redundant write is denied — the user is a member either way.
  Future<void> joinRoom(String roomId) {
    return _guard('joinRoom($roomId)', () async {
      final uid = await _uid();
      final ref = _members(roomId).doc(uid);
      if ((await ref.get()).exists) return;
      await ref.set({'joinedAt': FieldValue.serverTimestamp()});
    });
  }

  /// Removes the signed-in user from [roomId]'s roster (trigger decrements).
  Future<void> leaveRoom(String roomId) {
    return _guard('leaveRoom($roomId)', () async {
      final uid = await _uid();
      await _members(roomId).doc(uid).delete();
    });
  }
}
