import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../data/models/ani_video.dart';
import '../data/models/post.dart';
import 'auth_service.dart';
import 'follow_service.dart';

/// Ani Videos (short vertical video feed), backed by the top-level
/// `ani_videos` collection with `comments` and `likes` subcollections per
/// video — the same shape as FeedService's `posts`.
///
/// Video files live in Storage at `ani_videos/{userId}/{videoId}.mp4` with a
/// first-frame JPEG thumbnail next to them ({videoId}.jpg). Identity comes
/// from [AuthService.initAuth]; all writes go through [_guard] so failures
/// are logged and rethrown for the UI to surface.
class AniVideoService {
  AniVideoService._();
  static final AniVideoService instance = AniVideoService._();

  static const int pageSize = 10;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _videos => _db.collection('ani_videos');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[AniVideoService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AniVideoService] $op failed: $e');
      rethrow;
    }
  }

  /// Pin pending server timestamps (null createdAt) to the top so a just
  /// -uploaded video doesn't flash to the bottom — same trick as the feed.
  List<AniVideoData> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(AniVideoData.fromDoc).toList();
    list.sort((a, b) {
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return list;
  }

  // ── Feed reads ─────────────────────────────────────────────────────────

  /// Real-time global feed, newest first. Pagination is a growing [limit]
  /// (same pattern as feed comments): the screen bumps it by [pageSize] as
  /// the user swipes near the end. A following-based feed can layer on later,
  /// mirroring FeedService's fallback split.
  Stream<List<AniVideoData>> getVideoFeed({int limit = pageSize}) {
    return _videos.orderBy('createdAt', descending: true).limit(limit).snapshots().map(_sorted);
  }

  /// Live view of one video — null once deleted.
  Stream<AniVideoData?> watchVideo(String videoId) =>
      _videos.doc(videoId).snapshots().map((doc) => doc.exists ? AniVideoData.fromDoc(doc) : null);

  // ── Upload ─────────────────────────────────────────────────────────────

  /// Upload [videoFile] + first-frame thumbnail to Storage, then create the
  /// Firestore doc. [durationSeconds] must be measured by the caller (via a
  /// VideoPlayerController) and is re-checked here; >60s throws [ArgumentError]
  /// before any bytes move. [onProgress] reports 0..1 for the video bytes.
  /// Returns the new video id.
  Future<String> uploadVideo({
    required File videoFile,
    required int durationSeconds,
    required String caption,
    int? anilistId,
    String? animeTitle,
    String? animeCover,
    bool isSpoiler = false,
    void Function(double progress)? onProgress,
  }) {
    return _guard('uploadVideo', () async {
      if (durationSeconds > AniVideoData.maxDurationSeconds) {
        throw ArgumentError('video exceeds ${AniVideoData.maxDurationSeconds}s');
      }
      final trimmed = caption.trim();
      final capped = trimmed.length > AniVideoData.maxCaptionLength
          ? trimmed.substring(0, AniVideoData.maxCaptionLength)
          : trimmed;

      final uid = await _uid();
      final doc = _videos.doc();
      final videoRef = FirebaseStorage.instance.ref('ani_videos/$uid/${doc.id}.mp4');

      final task = videoRef.putFile(videoFile, SettableMetadata(contentType: 'video/mp4'));
      final sub = task.snapshotEvents.listen((s) {
        if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
      });
      try {
        await task;
      } finally {
        await sub.cancel();
      }
      final videoUrl = await videoRef.getDownloadURL();

      // Thumbnail is best-effort: a video without one still renders (the
      // player's first frame covers it) — don't fail the whole upload.
      var thumbnailUrl = '';
      try {
        final bytes = await VideoThumbnail.thumbnailData(
          video: videoFile.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 720,
          quality: 75,
        );
        if (bytes != null) {
          final thumbRef = FirebaseStorage.instance.ref('ani_videos/$uid/${doc.id}.jpg');
          await thumbRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
          thumbnailUrl = await thumbRef.getDownloadURL();
        }
      } catch (e) {
        debugPrint('[AniVideoService] thumbnail failed (continuing): $e');
      }

      // Identity snapshot from users/{uid} — render fallback only; the
      // overlay resolves the live doc through identityProvider.
      final me = await FollowService.instance.getUser(uid);
      final video = AniVideoData(
        id: doc.id,
        userId: uid,
        userName: me?.nameToShow ?? '',
        userAvatar: me?.userAvatar ?? '',
        isVerified: me?.isVerified ?? false,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        caption: capped,
        anilistId: anilistId,
        animeTitle: animeTitle,
        animeCover: animeCover,
        hashtags: PostData.extractHashtags(capped),
        durationSeconds: durationSeconds,
        isSpoiler: isSpoiler,
      );

      final batch = _db.batch()..set(doc, video.toMap());
      for (final tag in video.hashtags) {
        batch.set(
          _db.collection('trending_hashtags').doc(tag),
          {'tag': tag, 'count': FieldValue.increment(1), 'lastUsed': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      return doc.id;
    });
  }

  Future<void> deleteVideo(String videoId) {
    return _guard('deleteVideo($videoId)', () async {
      final uid = await _uid();
      await _videos.doc(videoId).delete();
      // Storage cleanup is best-effort — rules only let the owner delete, and
      // an orphaned file must not resurrect the already-deleted doc's error.
      for (final ext in const ['mp4', 'jpg']) {
        try {
          await FirebaseStorage.instance.ref('ani_videos/$uid/$videoId.$ext').delete();
        } catch (e) {
          debugPrint('[AniVideoService] storage cleanup $videoId.$ext: $e');
        }
      }
    });
  }

  // ── Likes ──────────────────────────────────────────────────────────────

  Future<void> likeVideo(String videoId, String userId) {
    return _guard('like($videoId)', () async {
      final batch = _db.batch()
        ..set(_videos.doc(videoId).collection('likes').doc(userId),
            {'likedAt': FieldValue.serverTimestamp()})
        ..update(_videos.doc(videoId), {'likes': FieldValue.increment(1)});
      await batch.commit();
    });
  }

  Future<void> unlikeVideo(String videoId, String userId) {
    return _guard('unlike($videoId)', () async {
      final batch = _db.batch()
        ..delete(_videos.doc(videoId).collection('likes').doc(userId))
        ..update(_videos.doc(videoId), {'likes': FieldValue.increment(-1)});
      await batch.commit();
    });
  }

  Future<bool> isVideoLikedByUser(String videoId, String userId) {
    return _guard('isLiked($videoId)', () async {
      final doc = await _videos.doc(videoId).collection('likes').doc(userId).get();
      return doc.exists;
    });
  }

  // ── Comments (same shape as feed post comments) ────────────────────────

  Stream<List<CommentData>> getComments(String videoId, {int limit = 30}) {
    return _videos
        .doc(videoId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(CommentData.fromDoc).toList());
  }

  /// Commenter identity is snapshotted from `users/{uid}` like [uploadVideo]
  /// — a render fallback only; comment rows resolve the live doc.
  Future<String> addComment(String videoId, String content) {
    return _guard('comment($videoId)', () async {
      final trimmed = content.trim();
      if (trimmed.isEmpty) throw ArgumentError('comment is empty');
      final capped = trimmed.length > CommentData.maxContentLength
          ? trimmed.substring(0, CommentData.maxContentLength)
          : trimmed;

      final uid = await _uid();
      final me = await FollowService.instance.getUser(uid);
      final doc = _videos.doc(videoId).collection('comments').doc();
      final batch = _db.batch()
        ..set(
            doc,
            CommentData(
                    id: doc.id,
                    userId: uid,
                    userName: me?.nameToShow ?? '',
                    userAvatar: me?.userAvatar ?? '',
                    content: capped)
                .toMap())
        ..update(_videos.doc(videoId), {'commentsCount': FieldValue.increment(1)});
      await batch.commit();
      return doc.id;
    });
  }

  Future<void> deleteComment(String videoId, String commentId) {
    return _guard('deleteComment($videoId/$commentId)', () async {
      final batch = _db.batch()
        ..delete(_videos.doc(videoId).collection('comments').doc(commentId))
        ..update(_videos.doc(videoId), {'commentsCount': FieldValue.increment(-1)});
      await batch.commit();
    });
  }

  // ── Reports, shares & views ────────────────────────────────────────────

  Future<void> reportVideo(String videoId, String reason) {
    return _guard('report($videoId)', () async {
      final uid = await _uid();
      await _db.collection('reports').add({
        'videoId': videoId,
        'reason': reason,
        'reporterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Fire-and-forget: a failed share bump must never surface in the UI.
  void incrementShareCount(String videoId) {
    _videos.doc(videoId).update({'shareCount': FieldValue.increment(1)}).catchError(
        (Object e) => debugPrint('[AniVideoService] shareCount($videoId) failed: $e'));
  }

  // One view per video per app session — the debounce the play-loop needs
  // (autoplay + looping would otherwise bump on every replay).
  final Set<String> _viewedThisSession = {};

  /// Fire-and-forget, once per playback session.
  void incrementView(String videoId) {
    if (!_viewedThisSession.add(videoId)) return;
    _videos.doc(videoId).update({'viewCount': FieldValue.increment(1)}).catchError((Object e) {
      _viewedThisSession.remove(videoId); // let a later session retry
      debugPrint('[AniVideoService] viewCount($videoId) failed: $e');
    });
  }
}
