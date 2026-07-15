import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/news.dart';
import 'auth_service.dart';

/// Curated anime news, backed by the admin-managed `news` collection.
///
/// Clients read in real time and may only bump the views/saves tallies
/// (±1, enforced by rules); articles are added via the Firebase Console —
/// no external feed dependency for the MVP. Because reads are live
/// snapshot listeners, "refresh every 30 minutes" comes for free: new
/// articles stream in the moment the admin publishes them.
class NewsService {
  NewsService._();
  static final NewsService instance = NewsService._();

  static const int pageSize = 50;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _news => _db.collection('news');

  Future<String> _uid() async => (await AuthService.instance.initAuth()).uid;

  Future<T> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return await body();
    } on FirebaseException catch (e) {
      debugPrint('[NewsService] $op failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[NewsService] $op failed: $e');
      rethrow;
    }
  }

  /// Category values for the filter chips ("All" + the real categories).
  List<NewsCategory> getNewsCategories() => const [
        NewsCategory.announcement,
        NewsCategory.season,
        NewsCategory.movie,
        NewsCategory.collab,
        NewsCategory.event,
      ];

  Query<Map<String, dynamic>> _query(NewsCategory? category, int limit) {
    Query<Map<String, dynamic>> q = _news;
    // Filtered queries use the (category, publishedAt) composite index.
    if (category != null) q = q.where('category', isEqualTo: category.value);
    return q.orderBy('publishedAt', descending: true).limit(limit);
  }

  /// Live articles, newest first. [category] null = all.
  Stream<List<NewsArticle>> getNewsArticles({NewsCategory? category, int limit = pageSize}) =>
      _query(category, limit).snapshots().map((s) => s.docs.map(NewsArticle.fromDoc).toList());

  /// Next page after [last] for infinite scroll.
  Future<List<NewsArticle>> fetchMoreNews(NewsArticle last,
      {NewsCategory? category, int limit = pageSize}) {
    return _guard('fetchMoreNews', () async {
      final cursor = last.publishedAt;
      if (cursor == null) return const <NewsArticle>[];
      final snap = await _query(category, limit).startAfter([Timestamp.fromDate(cursor)]).get();
      return snap.docs.map(NewsArticle.fromDoc).toList();
    });
  }

  /// Client-side substring match over the newest 100 articles — plenty for a
  /// curated collection; swap for a search index if the archive grows.
  Stream<List<NewsArticle>> searchNews(String query) {
    final q = query.trim().toLowerCase();
    return getNewsArticles(limit: 100).map((articles) => articles
        .where((a) => a.title.toLowerCase().contains(q) || a.description.toLowerCase().contains(q))
        .toList());
  }

  // ── Engagement ─────────────────────────────────────────────────────────

  /// Fire-and-forget: a failed view bump must never surface in the UI.
  void incrementViews(String newsId) {
    _news.doc(newsId).update({'views': FieldValue.increment(1)}).catchError(
        (Object e) => debugPrint('[NewsService] views($newsId) failed: $e'));
  }

  /// Save-for-later: `users/{uid}/savedNews/{newsId}` + saves tally.
  Future<void> saveArticle(String newsId) {
    return _guard('save($newsId)', () async {
      final uid = await _uid();
      final batch = _db.batch()
        ..set(_db.collection('users').doc(uid).collection('savedNews').doc(newsId),
            {'savedAt': FieldValue.serverTimestamp()})
        ..update(_news.doc(newsId), {'saves': FieldValue.increment(1)});
      await batch.commit();
    });
  }

  Future<void> unsaveArticle(String newsId) {
    return _guard('unsave($newsId)', () async {
      final uid = await _uid();
      final batch = _db.batch()
        ..delete(_db.collection('users').doc(uid).collection('savedNews').doc(newsId))
        ..update(_news.doc(newsId), {'saves': FieldValue.increment(-1)});
      await batch.commit();
    });
  }

  Stream<bool> watchIsSaved(String newsId) async* {
    final uid = await _uid();
    yield* _db
        .collection('users')
        .doc(uid)
        .collection('savedNews')
        .doc(newsId)
        .snapshots()
        .map((d) => d.exists);
  }

  Future<void> reportNews(String newsId, String reason) {
    return _guard('report($newsId)', () async {
      final uid = await _uid();
      await _db.collection('reports').add({
        'newsId': newsId,
        'reason': reason,
        'reporterId': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
