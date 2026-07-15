import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Optional anime tag on a story. The sticker's pixels are baked into the
/// image; this is the structured half: the AniList reference (id ONLY —
/// project rule: never copy AniList data; the viewer re-fetches via the
/// shared fetchById path) plus the sticker's rect normalized to the image
/// (fractions 0..1 of width/height), so any viewer can map a tap hotspot
/// onto the baked sticker regardless of its own screen size.
class StoryAnimeTag {
  final int anilistId;
  final double x, y, w, h; // left/top/width/height as fractions of the image

  const StoryAnimeTag({
    required this.anilistId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  Map<String, Object> toMap() => {'anilistId': anilistId, 'x': x, 'y': y, 'w': w, 'h': h};

  /// Null when [m] is missing or malformed (defensive against hand-written
  /// docs; the rules validate shape on create).
  static StoryAnimeTag? fromMap(Object? m) {
    if (m is! Map) return null;
    final id = m['anilistId'];
    final x = m['x'], y = m['y'], w = m['w'], h = m['h'];
    if (id is! int || id <= 0 || x is! num || y is! num || w is! num || h is! num) return null;
    return StoryAnimeTag(
        anilistId: id, x: x.toDouble(), y: y.toDouble(), w: w.toDouble(), h: h.toDouble());
  }
}

/// One person-mention on a story — the mirror of [StoryAnimeTag] for app
/// users: target `uid` ONLY (identity resolves live via `identityProvider`;
/// never denormalized) plus the sticker's rect normalized to the image.
class StoryMention {
  final String uid;
  final double x, y, w, h; // left/top/width/height as fractions of the image

  const StoryMention({
    required this.uid,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  Map<String, Object> toMap() => {'uid': uid, 'x': x, 'y': y, 'w': w, 'h': h};

  static StoryMention? fromMap(Object? m) {
    if (m is! Map) return null;
    final uid = m['uid'];
    final x = m['x'], y = m['y'], w = m['w'], h = m['h'];
    if (uid is! String || uid.isEmpty || x is! num || y is! num || w is! num || h is! num) return null;
    return StoryMention(
        uid: uid, x: x.toDouble(), y: y.toDouble(), w: w.toDouble(), h: h.toDouble());
  }
}

/// One story document (`stories/{storyId}`) — an image that expires 24h
/// after posting. Identity (name/avatar/verified) is NOT denormalized here;
/// render through `identityProvider(uid)`.
class StoryData {
  final String id;
  final String uid; // owner
  final String mediaUrl;
  final String caption; // '' if none
  final DateTime? createdAt; // null while the server timestamp is pending
  final DateTime? expiresAt;
  final StoryAnimeTag? animeTag;
  final List<StoryMention> mentions;

  const StoryData({
    required this.id,
    required this.uid,
    required this.mediaUrl,
    required this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.animeTag,
    this.mentions = const [],
  });

  bool get isActive => expiresAt != null && expiresAt!.isAfter(DateTime.now());

  factory StoryData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return StoryData(
      id: doc.id,
      uid: d['uid'] as String? ?? '',
      mediaUrl: d['mediaUrl'] as String? ?? '',
      caption: d['caption'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      animeTag: StoryAnimeTag.fromMap(d['animeTag']),
      mentions: d['mentions'] is List
          ? (d['mentions'] as List).map(StoryMention.fromMap).whereType<StoryMention>().toList()
          : const [],
    );
  }
}

/// Stories backend: `stories/{storyId}` docs + `stories/{uid}/{storyId}.jpg`
/// files. Read-model: recent stories stream, filtered to active (unexpired)
/// client-side. No counters are touched anywhere in this service.
class StoryService {
  StoryService._();
  static final StoryService instance = StoryService._();

  /// Caption hard cap — mirrored by the Firestore rule.
  static const int maxCaptionChars = 200;

  /// Mention cap per story — mirrored by the rule's unrolled list check.
  static const int maxMentions = 10;

  /// How many recent story docs the ring listens to (client filters expiry).
  static const int _windowLimit = 100;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _stories => _db.collection('stories');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[StoryService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[StoryService] $op failed: $e');
      rethrow;
    }
  }

  /// Recent stories, newest first, filtered to unexpired. The expiry filter
  /// is client-side (per emission), so a story vanishes on the next rebuild
  /// after its 24h are up without needing a server query per tick.
  Stream<List<StoryData>> getActiveStories() {
    return _stories
        .orderBy('createdAt', descending: true)
        .limit(_windowLimit)
        .snapshots()
        .map((snap) => snap.docs.map(StoryData.fromDoc).where((s) => s.isActive).toList());
  }

  /// Uploads [jpeg] (already compressed to the posts pipeline contract:
  /// JPEG, < 1 MB) and creates the story doc. `createdAt` is the server
  /// clock; `expiresAt` is client clock + 24h, which the Firestore rule
  /// range-checks against the server clock (future, under 25h out).
  /// [animeTag] and [mentions] are the optional structured halves of the
  /// anime/person stickers whose pixels are already baked into [jpeg].
  Future<String> createStory(
    Uint8List jpeg, {
    String caption = '',
    StoryAnimeTag? animeTag,
    List<StoryMention> mentions = const [],
  }) {
    return _guard('createStory', () async {
      final uid = await _uid();
      final doc = _stories.doc();
      final file = FirebaseStorage.instance.ref('stories/$uid/${doc.id}.jpg');
      await file.putData(jpeg, SettableMetadata(contentType: 'image/jpeg'));
      final mediaUrl = await file.getDownloadURL();

      final expiresAt = Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24)));
      final trimmed = caption.trim();
      try {
        await doc.set({
          'uid': uid,
          'mediaUrl': mediaUrl,
          if (trimmed.isNotEmpty)
            'caption': trimmed.length <= maxCaptionChars ? trimmed : trimmed.substring(0, maxCaptionChars),
          if (animeTag != null) 'animeTag': animeTag.toMap(),
          if (mentions.isNotEmpty)
            'mentions': mentions.take(maxMentions).map((m) => m.toMap()).toList(),
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': expiresAt,
        });
      } catch (_) {
        // Roll back the orphaned file so a failed doc write leaves nothing.
        try {
          await file.delete();
        } catch (e) {
          debugPrint('[StoryService] rollback delete failed: $e');
        }
        rethrow;
      }
      return doc.id;
    });
  }

  /// Records that the signed-in user viewed [storyId]. Create-only: the
  /// rules forbid updates, so an existing doc is left untouched (the get()
  /// guard avoids tripping the rule; a lost race is harmless).
  Future<void> markViewed(String storyId) {
    return _guard('markViewed', () async {
      final uid = await _uid();
      final ref = _stories.doc(storyId).collection('viewers').doc(uid);
      if ((await ref.get()).exists) return;
      await ref.set({'viewedAt': FieldValue.serverTimestamp()});
    });
  }

  /// Whether the signed-in user has viewed [storyId].
  Future<bool> hasViewed(String storyId) {
    return _guard('hasViewed', () async {
      final uid = await _uid();
      return (await _stories.doc(storyId).collection('viewers').doc(uid).get()).exists;
    });
  }

  /// Owner-only delete: doc first (rules-checked), then the Storage file.
  Future<void> deleteStory(StoryData story) {
    return _guard('deleteStory', () async {
      final uid = await _uid();
      await _stories.doc(story.id).delete();
      try {
        await FirebaseStorage.instance.ref('stories/$uid/${story.id}.jpg').delete();
      } catch (e) {
        debugPrint('[StoryService] storage cleanup failed (doc already gone): $e');
      }
    });
  }
}
