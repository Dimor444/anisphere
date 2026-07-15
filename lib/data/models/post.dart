import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'post_model.dart';

/// A feed post, stored at `posts/{postId}`.
///
/// Author fields (userName/userAvatar/isVerified) are denormalized snapshots
/// taken at post time so the feed renders without N extra user lookups; the
/// source of truth for a user's profile stays in `users/{userId}`. Anime
/// references carry only `anilist_id` + display title/cover — full metadata is
/// fetched from AniList on demand (same policy as My List).
class PostData {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final bool isVerified;
  final String content;
  final int? anilistId;
  final String? animeTitle;
  final String? animeCover;
  final List<String> imageUrls; // 0-3 attached images, in selection order
  final List<String> hashtags;
  final DateTime? createdAt; // null while a serverTimestamp is pending
  final DateTime? updatedAt;
  final int likes;
  final int commentsCount;
  final int viewCount;
  final bool isSpoiler;

  /// True for demo/sample posts that have no Firestore document behind them —
  /// interactions on those stay local (no writes, no detail navigation).
  final bool isLocal;

  static const int maxContentLength = 500;

  const PostData({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar = '',
    this.isVerified = false,
    required this.content,
    this.anilistId,
    this.animeTitle,
    this.animeCover,
    this.imageUrls = const [],
    this.hashtags = const [],
    this.createdAt,
    this.updatedAt,
    this.likes = 0,
    this.commentsCount = 0,
    this.viewCount = 0,
    this.isSpoiler = false,
    this.isLocal = false,
  });

  /// `#anime`, `#呪術廻戦`, `#jujutsu_kaisen` — letters/digits/underscore in any
  /// script. Stored lowercased and without the leading `#`.
  static final RegExp hashtagPattern = RegExp(r'#[\p{L}\p{N}_]+', unicode: true);

  static List<String> extractHashtags(String content) => hashtagPattern
      .allMatches(content)
      .map((m) => m.group(0)!.substring(1).toLowerCase())
      .toSet()
      .toList();

  /// New posts write `imageUrls`; posts from before multi-image support wrote
  /// a single `imageUrl` — folded into the list here so every reader has one
  /// render path. Missing both means a text-only post.
  @visibleForTesting
  static List<String> imageUrlsFromMap(Map<String, dynamic> d) {
    final list = (d['imageUrls'] as List<dynamic>?)?.cast<String>();
    if (list != null && list.isNotEmpty) return list;
    final legacy = d['imageUrl'] as String?;
    return (legacy == null || legacy.isEmpty) ? const [] : [legacy];
  }

  factory PostData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return PostData(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? '',
      userAvatar: d['userAvatar'] as String? ?? '',
      isVerified: d['isVerified'] as bool? ?? false,
      content: d['content'] as String? ?? '',
      anilistId: (d['anilist_id'] as num?)?.toInt(),
      animeTitle: d['animeTitle'] as String?,
      animeCover: d['animeCover'] as String?,
      imageUrls: imageUrlsFromMap(d),
      hashtags: (d['hashtags'] as List<dynamic>?)?.cast<String>() ?? const [],
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      likes: (d['likes'] as num?)?.toInt() ?? 0,
      commentsCount: (d['commentsCount'] as num?)?.toInt() ?? 0,
      viewCount: (d['viewCount'] as num?)?.toInt() ?? 0,
      isSpoiler: d['isSpoiler'] as bool? ?? false,
    );
  }

  /// Firestore payload (no id — that's the document key). Null timestamps
  /// become server timestamps so `createPost` writes are clock-skew safe.
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'isVerified': isVerified,
        'content': content,
        'anilist_id': anilistId,
        'animeTitle': animeTitle,
        'animeCover': animeCover,
        'imageUrls': imageUrls,
        'hashtags': hashtags,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
        'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
        'likes': likes,
        'commentsCount': commentsCount,
        'viewCount': viewCount,
        'isSpoiler': isSpoiler,
      };

  PostData copyWith({int? likes, int? commentsCount, int? viewCount}) {
    return PostData(
      id: id,
      userId: userId,
      userName: userName,
      userAvatar: userAvatar,
      isVerified: isVerified,
      content: content,
      anilistId: anilistId,
      animeTitle: animeTitle,
      animeCover: animeCover,
      imageUrls: imageUrls,
      hashtags: hashtags,
      createdAt: createdAt,
      updatedAt: updatedAt,
      likes: likes ?? this.likes,
      commentsCount: commentsCount ?? this.commentsCount,
      viewCount: viewCount ?? this.viewCount,
      isSpoiler: isSpoiler,
      isLocal: isLocal,
    );
  }

  /// Bridge for the demo content in [SampleData] (club rooms etc.) so the one
  /// PostCard widget renders both real and sample posts.
  factory PostData.fromSample(PostModel p) {
    return PostData(
      id: p.id,
      userId: p.author.id,
      userName: p.author.username,
      isVerified: p.author.isVerified,
      content: p.text,
      animeTitle: p.animeTag,
      hashtags: extractHashtags(p.text),
      createdAt: p.time,
      likes: p.likes,
      commentsCount: p.comments,
      isSpoiler: p.isSpoiler,
      isLocal: true,
    );
  }
}

/// One comment, stored at `posts/{postId}/comments/{commentId}`.
class CommentData {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String content;
  final DateTime? createdAt;
  final int likes;

  static const int maxContentLength = 250;

  const CommentData({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatar = '',
    required this.content,
    this.createdAt,
    this.likes = 0,
  });

  factory CommentData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CommentData(
      id: doc.id,
      userId: d['userId'] as String? ?? '',
      userName: d['userName'] as String? ?? '',
      userAvatar: d['userAvatar'] as String? ?? '',
      content: d['content'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      likes: (d['likes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userAvatar': userAvatar,
        'content': content,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
        'likes': likes,
      };
}
