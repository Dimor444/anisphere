import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'post.dart';

/// One short-form video, stored at `ani_videos/{videoId}`.
///
/// Mirrors [PostData]: author fields are denormalized snapshots taken at
/// upload time, anime references carry only `anilist_id` + display title/cover
/// (full metadata comes from AniList on demand), and engagement counters are
/// bumped ±1 client-side in the same batch as the like/comment doc.
/// Comments reuse [CommentData] — same subcollection shape as feed posts.
class AniVideoData {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final bool isVerified;
  final String videoUrl;
  final String thumbnailUrl;
  final String caption;
  final int? anilistId;
  final String? animeTitle;
  final String? animeCover;
  final List<String> hashtags;
  final int durationSeconds;
  final int likes;
  final int commentsCount;
  final int shareCount;
  final int viewCount;
  final DateTime? createdAt; // null while a serverTimestamp is pending
  final bool isSpoiler;

  static const int maxCaptionLength = 200;
  static const int maxDurationSeconds = 120;

  /// The upload screen rounds a clip's length up, so any real clip measures
  /// at least this. Zero means the player could not read a duration at all.
  static const int minDurationSeconds = 1;

  /// Hard ceiling on the clip's bytes, mirrored by the Cloud Function.
  ///
  /// Doubling the duration doubled the bytes, and the migration to R2 dropped
  /// the only size limit that existed: the old Firebase Storage rule capped
  /// video at 50 MB, and R2 enforces nothing of its own. The client checks
  /// this before asking for a url; the server signs the exact length into the
  /// presigned PUT so R2 rejects a body of any other size.
  static const int maxUploadBytes = 150 * 1024 * 1024;
  static const int maxUploadMb = 150;

  const AniVideoData({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar = '',
    this.isVerified = false,
    required this.videoUrl,
    this.thumbnailUrl = '',
    this.caption = '',
    this.anilistId,
    this.animeTitle,
    this.animeCover,
    this.hashtags = const [],
    this.durationSeconds = 0,
    this.likes = 0,
    this.commentsCount = 0,
    this.shareCount = 0,
    this.viewCount = 0,
    this.createdAt,
    this.isSpoiler = false,
  });

  /// Reads a stored video, or null when the document is not one the app
  /// could have written: a field of another type, or no date while no write
  /// from this device is pending.
  ///
  /// The rules check a video's shape only from 2026-10-13, and never reach
  /// what was stored before. A reader that throws on one document fails the
  /// whole snapshot it arrived in — every video on that feed page — so every
  /// read of a video goes through here and loses only the one it cannot
  /// read. Dropped videos are logged, not shown.
  static AniVideoData? tryFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    try {
      final video = AniVideoData.fromMap(doc.id, d);
      // A serverTimestamp reads as null only on the device that wrote it,
      // until the server answers. Stored without one, it is not our upload.
      if (video.createdAt == null && !doc.metadata.hasPendingWrites) {
        throw const FormatException('createdAt is missing');
      }
      return video;
    } on FormatException catch (e) {
      debugPrint('[AniVideoData] dropped ani_videos/${doc.id}: ${e.message}');
      return null;
    }
  }

  /// Reads [d], throwing [FormatException] for any field that holds a value
  /// of another type than [toMap] writes. Absent and null fields take their
  /// defaults, as they always have.
  @visibleForTesting
  factory AniVideoData.fromMap(String id, Map<String, dynamic> d) {
    T? read<T>(String key) {
      final v = d[key];
      if (v == null || v is T) return v as T?;
      throw FormatException('$key is ${v.runtimeType}, not $T');
    }

    // num, not int: a number stored as a double still reads. NaN and the
    // infinities do not — toInt() throws on them.
    int? readInt(String key) {
      final v = read<num>(key);
      if (v != null && !v.isFinite) throw FormatException('$key is $v');
      return v?.toInt();
    }

    // Checked here rather than with cast<String>(), which is lazy: it would
    // let the read succeed and throw later, wherever the list is used.
    final tags = read<List<dynamic>>('hashtags');
    if (tags != null && tags.any((t) => t is! String)) {
      throw const FormatException('hashtags holds a value that is not a string');
    }

    return AniVideoData(
      id: id,
      userId: read<String>('userId') ?? '',
      userName: read<String>('userName') ?? '',
      userAvatar: read<String>('userAvatar') ?? '',
      isVerified: read<bool>('isVerified') ?? false,
      videoUrl: read<String>('videoUrl') ?? '',
      thumbnailUrl: read<String>('thumbnailUrl') ?? '',
      caption: read<String>('caption') ?? '',
      anilistId: readInt('anilist_id'),
      animeTitle: read<String>('animeTitle'),
      animeCover: read<String>('animeCover'),
      hashtags: tags == null ? const [] : List<String>.unmodifiable(tags),
      durationSeconds: readInt('durationSeconds') ?? 0,
      likes: readInt('likes') ?? 0,
      commentsCount: readInt('commentsCount') ?? 0,
      shareCount: readInt('shareCount') ?? 0,
      viewCount: readInt('viewCount') ?? 0,
      createdAt: read<Timestamp>('createdAt')?.toDate(),
      isSpoiler: read<bool>('isSpoiler') ?? false,
    );
  }

  /// Firestore payload (no id — that's the document key). Null timestamps
  /// become server timestamps so upload writes are clock-skew safe.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'isVerified': isVerified,
        'videoUrl': videoUrl,
        'thumbnailUrl': thumbnailUrl,
        'caption': caption,
        'anilist_id': anilistId,
        'animeTitle': animeTitle,
        'animeCover': animeCover,
        'hashtags': hashtags,
        'durationSeconds': durationSeconds,
        'likes': likes,
        'commentsCount': commentsCount,
        'shareCount': shareCount,
        'viewCount': viewCount,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
        'isSpoiler': isSpoiler,
      };

  AniVideoData copyWith({int? likes, int? commentsCount, int? shareCount, int? viewCount}) {
    return AniVideoData(
      id: id,
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      isVerified: isVerified,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      caption: caption,
      anilistId: anilistId,
      animeTitle: animeTitle,
      animeCover: animeCover,
      hashtags: hashtags,
      durationSeconds: durationSeconds,
      likes: likes ?? this.likes,
      commentsCount: commentsCount ?? this.commentsCount,
      shareCount: shareCount ?? this.shareCount,
      viewCount: viewCount ?? this.viewCount,
      createdAt: createdAt,
      isSpoiler: isSpoiler,
    );
  }
}
