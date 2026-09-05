import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../data/models/ani_video.dart';
import '../data/models/post.dart';
import 'auth_service.dart';
import 'follow_service.dart';

/// The upload was refused by a limit — the caller's quota, or the file size.
///
/// Distinct from a transport failure on purpose: retrying cannot help, so the
/// UI shows this text instead of the generic "try again" dialog. [message] is
/// authored by the Cloud Function or by the local size check, and is
/// English-only in both cases.
class UploadCapExceededException implements Exception {
  const UploadCapExceededException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A server-issued permit for one upload: where to PUT each file, the exact
/// Content-Type each signature was computed over, and the public base the
/// read urls are composed from.
///
/// Nothing here is chosen by the client. The keys, the content types and the
/// expiry are all the function's decision, so the client cannot widen its own
/// grant by editing a url.
class _UploadGrant {
  const _UploadGrant({
    required this.publicBase,
    required this.videoUploadUrl,
    required this.videoKey,
    required this.videoContentType,
    required this.videoContentLength,
    required this.thumbUploadUrl,
    required this.thumbKey,
    required this.thumbContentType,
  });

  /// Callable results arrive as `Map<Object?, Object?>` on iOS rather than
  /// `Map<String, dynamic>`, so every level is re-wrapped rather than cast.
  factory _UploadGrant.fromCallable(Object? data) {
    final root = Map<String, dynamic>.from(data! as Map);
    final video = Map<String, dynamic>.from(root['video'] as Map);
    final thumb = Map<String, dynamic>.from(root['thumbnail'] as Map);
    return _UploadGrant(
      publicBase: root['publicBase'] as String,
      videoUploadUrl: video['uploadUrl'] as String,
      videoKey: video['key'] as String,
      videoContentType: video['contentType'] as String,
      videoContentLength: (video['contentLength'] as num).toInt(),
      thumbUploadUrl: thumb['uploadUrl'] as String,
      thumbKey: thumb['key'] as String,
      thumbContentType: thumb['contentType'] as String,
    );
  }

  final String publicBase;
  final String videoUploadUrl;
  final String videoKey;
  final String videoContentType;

  /// The byte count the server signed into [videoUploadUrl]. The PUT must
  /// declare exactly this or R2 rejects it, so it is echoed back rather than
  /// re-measured on the client.
  final int videoContentLength;

  final String thumbUploadUrl;
  final String thumbKey;
  final String thumbContentType;

  String get videoUrl => '$publicBase/$videoKey';
  String get thumbnailUrl => '$publicBase/$thumbKey';
}

/// A PUT whose body is streamed from a [Stream], with the byte counter
/// advancing at transmission pace.
///
/// [http.BaseRequest] is subclassed rather than using [http.StreamedRequest]
/// because the client PULLS from the stream returned by [finalize]: the
/// counter therefore ticks as bytes go to the socket, and backpressure is the
/// socket's. Pushing into a StreamedRequest's sink instead counts bytes as
/// they are BUFFERED, which for a 50 MB clip races the bar to 100% while the
/// network is still working — and deadlocks outright if `send` is awaited
/// before the sink is fed.
class _StreamedPut extends http.BaseRequest {
  _StreamedPut(Uri url, this._body, int length) : super('PUT', url) {
    contentLength = length;
  }

  final Stream<List<int>> _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_body);
  }
}

/// Ani Videos (short vertical video feed), backed by the top-level
/// `ani_videos` collection with `comments` and `likes` subcollections per
/// video — the same shape as FeedService's `posts`.
///
/// Video BYTES live in Cloudflare R2, not Firebase Storage: the client asks
/// [requestVideoUploadUrl] for presigned PUT urls, uploads straight to R2, and
/// composes the read url from the `publicBase` the function hands back. The
/// object keys still read `ani_videos/{userId}/{videoId}.(mp4|jpg)`, so the
/// layout is unchanged — only the host is. Everything else (documents,
/// counters, comments, likes) stays in Firestore.
///
/// Identity comes from [AuthService.initAuth]; all writes go through [_guard]
/// so failures are logged and rethrown for the UI to surface.
class AniVideoService {
  AniVideoService._();
  static final AniVideoService instance = AniVideoService._();

  static const int pageSize = 10;

  /// Region the presigner is deployed to. `FirebaseFunctions.instance`
  /// defaults to us-central1, where this function does not exist — an
  /// unregioned call fails NOT_FOUND rather than falling back.
  static const String _functionsRegion = 'europe-west1';

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

  /// Allocates the document id an upload will use, writing nothing.
  ///
  /// Hoisted out of [uploadVideo] so a retry can pass the SAME id back in.
  /// Every distinct id costs a server-side upload grant, so minting a fresh
  /// one per attempt would let three failed retries burn a guest's entire day.
  String newVideoId() => _videos.doc().id;

  /// Asks the server for presigned R2 PUT urls for [videoId].
  ///
  /// This is the gate: the function validates the id, resolves the caller's
  /// tier, enforces the per-tier caps and records the grant before any url
  /// exists. A refusal for quota is translated into
  /// [UploadCapExceededException] so the UI can say why instead of offering a
  /// retry that cannot succeed.
  Future<_UploadGrant> _requestUploadUrls(String videoId, int contentLength) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('requestVideoUploadUrl')
          .call<Object?>({'videoId': videoId, 'contentLength': contentLength});
      return _UploadGrant.fromCallable(result.data);
    } on FirebaseFunctionsException catch (e) {
      // Both are limits the user has to act on, not transient faults:
      // resource-exhausted is the quota, out-of-range is the size cap.
      if (e.code == 'resource-exhausted' || e.code == 'out-of-range') {
        throw UploadCapExceededException(e.message ?? 'Upload limit reached.');
      }
      rethrow;
    }
  }

  /// PUTs [body] to a presigned url.
  ///
  /// [length] becomes the request's `Content-Length`. For the clip that value
  /// is inside the SigV4 signature (`X-Amz-SignedHeaders: content-length;host`
  /// — verified against the presigner), so R2 refuses a body of any other
  /// size. Setting `contentLength` on the request is what makes package:http
  /// emit the header, which is why the body is a Stream with an explicit
  /// length rather than a buffered list.
  ///
  /// [contentType] is sent verbatim: it is the type R2 stores and serves back,
  /// and video_player infers the container from it. It is NOT signed — a
  /// presigned PutObject lists only `host` unless a header like content-length
  /// is added — so this header is required for playback, not for the
  /// signature. The body is still always bytes, never a String: package:http
  /// appends `; charset=utf-8` to a String body's content type, which would
  /// change the stored type.
  Future<void> _put(
    String url,
    Stream<List<int>> body,
    int length,
    String contentType, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      var sent = 0;
      final counted = body.map((chunk) {
        sent += chunk.length;
        if (length > 0) onProgress?.call(sent / length);
        return chunk;
      });
      final request = _StreamedPut(Uri.parse(url), counted, length)
        ..headers['content-type'] = contentType;

      final response = await client.send(request);
      // Drain regardless: an undrained error body leaks the connection.
      final text = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException('R2 PUT failed ${response.statusCode}: $text', request.url);
      }
    } finally {
      client.close();
    }
  }

  /// Upload [videoFile] + first-frame thumbnail to R2, then create the
  /// Firestore doc. [videoId] comes from [newVideoId] and MUST be reused
  /// across retries of the same clip — see that method.
  ///
  /// [durationSeconds] must be measured by the caller (via a
  /// VideoPlayerController) and is re-checked here; >60s throws [ArgumentError]
  /// before any bytes move. [onProgress] reports 0..1 for the video bytes.
  /// Returns the video id.
  Future<String> uploadVideo({
    required File videoFile,
    required String videoId,
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
      final doc = _videos.doc(videoId);

      // Measured once and used for everything downstream: the local check,
      // the value sent to the server, and — via the grant's echo — the
      // Content-Length on the wire. One number, no chance of a mismatch.
      final contentLength = await videoFile.length();
      if (contentLength > AniVideoData.maxUploadBytes) {
        final mb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
        throw UploadCapExceededException(
          'This video is $mb MB. The limit is ${AniVideoData.maxUploadMb} MB.',
        );
      }

      // The gate. Nothing has been uploaded yet and nothing will be if the
      // caller is over quota or over the size cap — this throws before a
      // single byte moves.
      final grant = await _requestUploadUrls(videoId, contentLength);

      await _put(
        grant.videoUploadUrl,
        videoFile.openRead(),
        // The SIGNED length, not a fresh measurement — see the field's doc.
        grant.videoContentLength,
        grant.videoContentType,
        onProgress: onProgress,
      );
      final videoUrl = grant.videoUrl;

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
          // No onProgress: the bar belongs to the clip, and a thumbnail
          // finishing would otherwise snap it backwards.
          await _put(
            grant.thumbUploadUrl,
            Stream<List<int>>.value(bytes),
            bytes.length,
            grant.thumbContentType,
          );
          thumbnailUrl = grant.thumbnailUrl;
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

  /// Deletes the video: R2 objects first, then the Firestore document.
  ///
  /// The order is the whole point, and it is the reverse of what this used to
  /// do. Deleting the document first and sweeping storage afterwards meant any
  /// failure past the first step orphaned the bytes permanently — the keys
  /// exist only in the document, and the document was already gone, so nothing
  /// remembered what to clean up. Objects-first inverts the failure: if the
  /// document delete fails the bytes are gone but the video is still listed,
  /// which is visible, retryable, and converges (the callable re-checks
  /// ownership against the still-present document, and an S3 delete of an
  /// absent key succeeds).
  ///
  /// Neither step is best-effort any more. The callable throws on refusal —
  /// not the author, no such video — and that propagates instead of being
  /// swallowed, because silently reporting a delete that did not happen is
  /// how the orphans got there.
  Future<void> deleteVideo(String videoId) {
    return _guard('deleteVideo($videoId)', () async {
      // Server-side: the client has no R2 credentials and must never have any.
      await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('deleteVideoObjects')
          .call<Object?>({'videoId': videoId});
      await _videos.doc(videoId).delete();
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
