import 'package:cloud_firestore/cloud_firestore.dart';

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
  static const int maxDurationSeconds = 60;

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

  factory AniVideoData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return AniVideoData(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? '',
      userAvatar: d['userAvatar'] as String? ?? '',
      isVerified: d['isVerified'] as bool? ?? false,
      videoUrl: d['videoUrl'] as String? ?? '',
      thumbnailUrl: d['thumbnailUrl'] as String? ?? '',
      caption: d['caption'] as String? ?? '',
      anilistId: (d['anilist_id'] as num?)?.toInt(),
      animeTitle: d['animeTitle'] as String?,
      animeCover: d['animeCover'] as String?,
      hashtags: (d['hashtags'] as List<dynamic>?)?.cast<String>() ?? const [],
      durationSeconds: (d['durationSeconds'] as num?)?.toInt() ?? 0,
      likes: (d['likes'] as num?)?.toInt() ?? 0,
      commentsCount: (d['commentsCount'] as num?)?.toInt() ?? 0,
      shareCount: (d['shareCount'] as num?)?.toInt() ?? 0,
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      isSpoiler: d['isSpoiler'] as bool? ?? false,
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
