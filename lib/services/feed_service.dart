import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../data/models/post.dart';
import 'auth_service.dart';
import 'follow_service.dart';

/// The social feed, backed by the top-level `posts` collection with
/// `comments` and `likes` subcollections per post.
///
/// Identity comes from [AuthService.initAuth] (guest fallback), same as
/// MyListService. All writes go through [_guard] so failures are logged and
/// rethrown for the UI to surface (snackbar/dialog + retry).
///
/// Engagement counters (likes / commentsCount / viewCount) are bumped
/// client-side with `FieldValue.increment` in the same batch as the
/// like/comment document, and firestore.rules only admit ±1 counter-only
/// updates. When Cloud Functions land, the counter halves of these batches
/// move server-side and the rules tighten to `allow update: if false`.
class FeedService {
  FeedService._();
  static final FeedService instance = FeedService._();

  static const int pageSize = 20;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _posts => _db.collection('posts');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[FeedService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[FeedService] $op failed: $e');
      rethrow;
    }
  }

  /// Pin pending server timestamps (null createdAt) to the top so a just
  /// -created post doesn't flash to the bottom — same trick as My List.
  List<PostData> _sorted(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(PostData.fromDoc).toList();
    list.sort((a, b) {
      if (a.createdAt == null) return -1;
      if (b.createdAt == null) return 1;
      return b.createdAt!.compareTo(a.createdAt!);
    });
    return list;
  }

  // ── Feed reads ─────────────────────────────────────────────────────────

  /// Real-time first page of the feed, newest first — posts from followed
  /// users plus the user's own (never a global firehose). Follow data comes
  /// from FollowService; authors are capped at Firestore's 30-value whereIn
  /// limit. Requires the (userId ASC, createdAt DESC) composite index —
  /// see firestore.indexes.json. Older pages come from [fetchMorePosts].
  Stream<List<PostData>> getFeedPosts({int limit = pageSize}) async* {
    final uid = await _uid();
    final following = await FollowService.instance.followingIds();
    yield* _feedQuery(following, uid, limit).snapshots().map(_sorted);
  }

  Query<Map<String, dynamic>> _feedQuery(List<String> following, String uid, int limit) {
    final authors = {uid, ...following}.take(FollowService.feedAuthorCap).toList();
    return _posts
        .where('userId', whereIn: authors)
        .orderBy('createdAt', descending: true)
        .limit(limit);
  }

  /// Next page after [last] (cursor on createdAt). Returns fewer than [limit]
  /// items — possibly none — when the feed is exhausted.
  Future<List<PostData>> fetchMorePosts(PostData last, {int limit = pageSize}) {
    return _guard('fetchMore', () async {
      final cursor = last.createdAt;
      if (cursor == null) return const <PostData>[];
      final uid = await _uid();
      final following = await FollowService.instance.followingIds();
      final snap = await _feedQuery(following, uid, limit)
          .startAfter([Timestamp.fromDate(cursor)]).get();
      return _sorted(snap);
    });
  }

  // Popular-posts memo: last computed list + when, so re-opening the feed
  // within [_popularTtl] paints instantly without waiting on the query.
  List<PostData>? _popularCache;
  DateTime _popularCachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _popularTtl = Duration(hours: 1);

  /// Most-liked posts of the last [days] days — the feed fallback for users
  /// who follow nobody yet.
  ///
  /// Firestore can't range-filter createdAt AND order by likes in one query,
  /// so this pulls the newest 100 posts in the window and ranks by likes
  /// (then recency) client-side — fine at MVP scale. Live: new likes reorder
  /// the list as they happen.
  Stream<List<PostData>> getPopularPosts({int days = 7, int limit = 20}) async* {
    final fresh = _popularCache != null &&
        DateTime.now().difference(_popularCachedAt) < _popularTtl;
    if (fresh) yield _popularCache!.take(limit).toList();

    final cutoff = Timestamp.fromDate(DateTime.now().subtract(Duration(days: days)));
    yield* _posts
        .where('createdAt', isGreaterThan: cutoff)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) {
      final ranked = snap.docs.map(PostData.fromDoc).toList()
        ..sort((a, b) {
          final byLikes = b.likes.compareTo(a.likes);
          if (byLikes != 0) return byLikes;
          return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
        });
      _popularCache = ranked;
      _popularCachedAt = DateTime.now();
      return ranked.take(limit).toList();
    });
  }

  Future<bool> isUserFollowingAnyone(String userId) async =>
      FollowService.instance.hasAnyFollowing();

  /// A single user's posts, newest first (profile "Posts" tab).
  /// No orderBy in the query (keeps it index-free); sorted client-side.
  Stream<List<PostData>> getUserPosts(String userId, {int limit = 50}) {
    return _posts.where('userId', isEqualTo: userId).limit(limit).snapshots().map(_sorted);
  }

  /// Posts carrying [tag] (lowercase, no '#'), newest first.
  Stream<List<PostData>> getHashtagPosts(String tag, {int limit = 50}) {
    return _posts
        .where('hashtags', arrayContains: tag.toLowerCase())
        .limit(limit)
        .snapshots()
        .map(_sorted);
  }

  /// Live view of one post — null once deleted.
  Stream<PostData?> watchPost(String postId) =>
      _posts.doc(postId).snapshots().map((doc) => doc.exists ? PostData.fromDoc(doc) : null);

  // ── Post writes ────────────────────────────────────────────────────────

  /// Bumped after every successful post create/delete commit. The
  /// relationship-derived post-count provider re-runs its count()
  /// aggregation when this changes — display never reads the denormalized
  /// postsCount field (write-only bookkeeping, kept byte-identical).
  final ValueNotifier<int> postsEpoch = ValueNotifier(0);

  /// Client-generated id for a post that hasn't been written yet, so image
  /// uploads can target `posts/{uid}/{postId}/` before the doc exists and
  /// [createPost] then writes the doc under the same id.
  String newPostId() => _posts.doc().id;

  /// Publish a post. Hashtags are extracted here (client-side) and the
  /// `trending_hashtags` tallies are bumped in the same batch.
  ///
  /// Author identity comes from the user's own `users/{uid}` doc — the single
  /// source of truth. The copy written onto the post is a fallback for
  /// readers that haven't resolved the live doc yet; render sites always
  /// prefer identityProvider.
  ///
  /// Pass [postId] (from [newPostId]) when images were uploaded first so the
  /// doc id matches their Storage path.
  /// Returns the new post id.
  Future<String> createPost({
    required String content,
    String? postId,
    int? anilistId,
    String? animeTitle,
    String? animeCover,
    List<String> imageUrls = const [],
    bool isSpoiler = false,
  }) {
    return _guard('createPost', () async {
      final trimmed = content.trim();
      // Text or images — either alone is enough (image-only posts have an
      // empty caption); both empty is never a valid post.
      if (trimmed.isEmpty && imageUrls.isEmpty) {
        throw ArgumentError('post has no content and no images');
      }
      final capped = trimmed.length > PostData.maxContentLength
          ? trimmed.substring(0, PostData.maxContentLength)
          : trimmed;

      final uid = await _uid();
      final me = await FollowService.instance.getUser(uid);
      final post = PostData(
        id: '',
        userId: uid,
        userName: me?.nameToShow ?? '',
        userAvatar: me?.userAvatar ?? '',
        isVerified: me?.isVerified ?? false,
        content: capped,
        anilistId: anilistId,
        animeTitle: animeTitle,
        animeCover: animeCover,
        imageUrls: imageUrls,
        hashtags: PostData.extractHashtags(capped),
        isSpoiler: isSpoiler,
      );

      final doc = postId != null ? _posts.doc(postId) : _posts.doc();
      final batch = _db.batch()
        ..set(doc, post.toMap())
        ..update(_db.collection('users').doc(uid), {'postsCount': FieldValue.increment(1)});
      for (final tag in post.hashtags) {
        batch.set(
          _db.collection('trending_hashtags').doc(tag),
          {'tag': tag, 'count': FieldValue.increment(1), 'lastUsed': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      postsEpoch.value++;
      return doc.id;
    });
  }

  /// Upload compressed post images (each already asserted < 1 MB by
  /// PostImageCompressor) to `posts/{uid}/{postId}/{index}.jpg`; returns
  /// download URLs in the same order. All-or-nothing: if any upload fails,
  /// the already-uploaded files are deleted (best effort) and the error is
  /// rethrown so the caller never writes a half-broken post.
  Future<List<String>> uploadPostImages(String postId, List<Uint8List> images) {
    return _guard('uploadImages($postId)', () async {
      final uid = await _uid();
      final uploaded = <Reference>[];
      try {
        final urls = <String>[];
        for (var i = 0; i < images.length; i++) {
          final ref = FirebaseStorage.instance.ref('posts/$uid/$postId/$i.jpg');
          await ref.putData(images[i], SettableMetadata(contentType: 'image/jpeg'));
          uploaded.add(ref);
          urls.add(await ref.getDownloadURL());
        }
        return urls;
      } catch (_) {
        for (final ref in uploaded) {
          try {
            await ref.delete();
          } catch (e) {
            debugPrint('[FeedService] rollback of ${ref.fullPath} failed: $e');
          }
        }
        rethrow;
      }
    });
  }

  /// Best-effort cleanup of `posts/{uid}/{postId}/0.jpg … {count-1}.jpg` when
  /// the Firestore write fails after the images already uploaded.
  Future<void> deletePostImages(String postId, int count) async {
    final uid = await _uid();
    for (var i = 0; i < count; i++) {
      try {
        await FirebaseStorage.instance.ref('posts/$uid/$postId/$i.jpg').delete();
      } catch (e) {
        debugPrint('[FeedService] deletePostImages($postId/$i) failed: $e');
      }
    }
  }

  Future<void> deletePost(String postId) {
    return _guard('deletePost($postId)', () async {
      final uid = await _uid();
      final batch = _db.batch()
        ..delete(_posts.doc(postId))
        ..update(_db.collection('users').doc(uid), {'postsCount': FieldValue.increment(-1)});
      await batch.commit();
      postsEpoch.value++;
    });
  }

  // ── Likes ──────────────────────────────────────────────────────────────

  Future<void> likePost(String postId, String userId) {
    return _guard('like($postId)', () async {
      final batch = _db.batch()
        ..set(_posts.doc(postId).collection('likes').doc(userId),
            {'likedAt': FieldValue.serverTimestamp()})
        ..update(_posts.doc(postId), {'likes': FieldValue.increment(1)});
      await batch.commit();
    });
  }

  Future<void> unlikePost(String postId, String userId) {
    return _guard('unlike($postId)', () async {
      final batch = _db.batch()
        ..delete(_posts.doc(postId).collection('likes').doc(userId))
        ..update(_posts.doc(postId), {'likes': FieldValue.increment(-1)});
      await batch.commit();
    });
  }

  Future<bool> isPostLikedByUser(String postId, String userId) {
    return _guard('isLiked($postId)', () async {
      final doc = await _posts.doc(postId).collection('likes').doc(userId).get();
      return doc.exists;
    });
  }

  // ── Comments ───────────────────────────────────────────────────────────

  /// Newest first; [limit] grows for "load more" (subcollections stay small
  /// enough that a growing-limit listener beats cursor juggling here).
  Stream<List<CommentData>> getComments(String postId, {int limit = 30}) {
    return _posts
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(CommentData.fromDoc).toList());
  }

  /// Commenter identity is snapshotted from `users/{uid}` like [createPost] —
  /// a render fallback only; comment rows resolve the live doc.
  Future<String> addComment(String postId, String content) {
    return _guard('comment($postId)', () async {
      final trimmed = content.trim();
      if (trimmed.isEmpty) throw ArgumentError('comment is empty');
      final capped = trimmed.length > CommentData.maxContentLength
          ? trimmed.substring(0, CommentData.maxContentLength)
          : trimmed;

      final uid = await _uid();
      final me = await FollowService.instance.getUser(uid);
      final doc = _posts.doc(postId).collection('comments').doc();
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
        ..update(_posts.doc(postId), {'commentsCount': FieldValue.increment(1)});
      await batch.commit();
      return doc.id;
    });
  }

  Future<void> deleteComment(String postId, String commentId) {
    return _guard('deleteComment($postId/$commentId)', () async {
      final batch = _db.batch()
        ..delete(_posts.doc(postId).collection('comments').doc(commentId))
        ..update(_posts.doc(postId), {'commentsCount': FieldValue.increment(-1)});
      await batch.commit();
    });
  }

  // ── Reports & views ────────────────────────────────────────────────────

  Future<void> reportPost(String postId, String reason) {
    return _guard('report($postId)', () async {
      final uid = await _uid();
      await _db.collection('reports').add({
        'postId': postId,
        'reason': reason,
        'reporterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Fire-and-forget: a failed view bump must never surface in the UI.
  void incrementViewCount(String postId) {
    _posts.doc(postId).update({'viewCount': FieldValue.increment(1)}).catchError(
        (Object e) => debugPrint('[FeedService] viewCount($postId) failed: $e'));
  }
}
