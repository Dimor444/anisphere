import 'package:cloud_firestore/cloud_firestore.dart';

/// A community room, stored at `rooms/{roomId}`.
///
/// Only the Watch Party type exists today ([typeWatchParty]); [type] is the
/// discriminator so Art Room / Clubs can share the collection later.
///
/// The anime link is an AniList id ONLY — cover art and the canonical title
/// are fetched live at render time rather than denormalized here, matching how
/// Anime DNA and story anime tags store their AniList references.
///
/// [memberCount] is server-owned: rules deny client writes to it and the
/// `rooms/{roomId}/members/{uid}` Cloud Function trigger is the only writer.
/// Treat it as read-only from Dart.
class Room {
  static const String typeWatchParty = 'watch_party';

  final String id;
  final String type;
  final String title;

  /// AniList id of the related anime, or null when the room isn't tied to one.
  /// Stored as a string to keep the field shape stable if AniList ever hands
  /// out non-numeric ids.
  final String? animeId;
  final int? episodeNumber;
  final String hostUid;
  final int memberCount;
  final bool isLive;
  final DateTime? createdAt;

  const Room({
    required this.id,
    this.type = typeWatchParty,
    required this.title,
    this.animeId,
    this.episodeNumber,
    required this.hostUid,
    this.memberCount = 0,
    this.isLive = false,
    this.createdAt,
  });

  factory Room.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Room(
      id: doc.id,
      type: d['type'] as String? ?? typeWatchParty,
      title: d['title'] as String? ?? '',
      animeId: d['animeId'] as String?,
      episodeNumber: (d['episodeNumber'] as num?)?.toInt(),
      hostUid: d['hostUid'] as String? ?? '',
      memberCount: (d['memberCount'] as num?)?.toInt() ?? 0,
      isLive: d['isLive'] as bool? ?? false,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// The create payload. memberCount is seeded at 0 and never sent again —
  /// the members trigger owns it from the first join onward. Optional fields
  /// are omitted rather than written as null, because the rules' `hasOnly`
  /// whitelist admits them only when present and well-typed.
  Map<String, dynamic> toCreateMap() => {
        'type': type,
        'title': title,
        if (animeId != null) 'animeId': animeId,
        if (episodeNumber != null) 'episodeNumber': episodeNumber,
        'hostUid': hostUid,
        'memberCount': 0,
        'isLive': isLive,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
