import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// News category — stored in Firestore as the [value] string. Each carries
/// its badge color and app_strings key.
enum NewsCategory {
  announcement('Announcement', 'catAnnouncement', Color(0xFF3B82F6)), // blue
  season('Season', 'catSeason', Color(0xFF8B5CF6)), // purple
  movie('Movie', 'catMovie', Color(0xFFF97316)), // orange
  collab('Collab', 'catCollab', Color(0xFF22C55E)), // green
  event('Event', 'catEvent', Color(0xFFEF4444)), // red
  news('News', 'news', Color(0xFF64748B)); // slate (default)

  final String value; // Firestore value
  final String trKey; // app_strings key for the label
  final Color color;
  const NewsCategory(this.value, this.trKey, this.color);

  static NewsCategory fromValue(String? v) =>
      NewsCategory.values.firstWhere((c) => c.value == v, orElse: () => NewsCategory.news);
}

/// One curated news article, stored at `news/{newsId}`.
///
/// The collection is admin-managed (Firebase Console / future admin panel) —
/// clients can only read and bump the views/saves tallies. Related anime are
/// referenced by anilist_id (+ display title so chips render without an
/// extra API call).
class NewsArticle {
  final String id;
  final String title;
  final String description;
  final NewsCategory category;
  final String source;
  final String? imageUrl;
  final List<int> animeIds;
  final List<String> animeTitles; // aligned with animeIds; may be shorter
  final DateTime? publishedAt;
  final String? sourceUrl;
  final int views;
  final int saves;

  static const int maxTitleLength = 150;
  static const int maxDescriptionLength = 500;

  const NewsArticle({
    required this.id,
    required this.title,
    this.description = '',
    this.category = NewsCategory.news,
    this.source = 'AniSphere',
    this.imageUrl,
    this.animeIds = const [],
    this.animeTitles = const [],
    this.publishedAt,
    this.sourceUrl,
    this.views = 0,
    this.saves = 0,
  });

  /// Title of the related anime at [index], or a generic fallback when the
  /// admin only supplied ids.
  String animeTitleAt(int index) =>
      index < animeTitles.length && animeTitles[index].isNotEmpty
          ? animeTitles[index]
          : 'Anime #${animeIds[index]}';

  factory NewsArticle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return NewsArticle(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      category: NewsCategory.fromValue(d['category'] as String?),
      source: d['source'] as String? ?? 'AniSphere',
      imageUrl: d['imageUrl'] as String?,
      animeIds: (d['animeIds'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? const [],
      animeTitles: (d['animeTitles'] as List<dynamic>?)?.cast<String>() ?? const [],
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
      sourceUrl: d['sourceUrl'] as String?,
      views: (d['views'] as num?)?.toInt() ?? 0,
      saves: (d['saves'] as num?)?.toInt() ?? 0,
    );
  }

  /// Firestore payload (no id). Client code never creates articles — this
  /// exists for admin tooling and tests.
  Map<String, dynamic> toMap() => {
        'title': title.length > maxTitleLength ? title.substring(0, maxTitleLength) : title,
        'description': description.length > maxDescriptionLength
            ? description.substring(0, maxDescriptionLength)
            : description,
        'category': category.value,
        'source': source,
        'imageUrl': imageUrl,
        'animeIds': animeIds,
        'animeTitles': animeTitles,
        'publishedAt': publishedAt != null ? Timestamp.fromDate(publishedAt!) : FieldValue.serverTimestamp(),
        'sourceUrl': sourceUrl,
        'views': views,
        'saves': saves,
      };
}
