import 'package:cloud_firestore/cloud_firestore.dart';

/// One cast vote, stored at `community_votes/{dayId}/votes/{userId}_{slot}`.
///
/// The doc id encodes user + slot so a slot can never be double-spent
/// (create-on-existing fails) and rules can pin creation to the voter.
/// Votes are FINAL: rules deny update/delete outright.
class CommunityVote {
  final String userId;
  final int anilistId;
  final String animeTitle;
  final String animeCover;
  final String dayId; // "YYYY-MM-DD" (UTC day)
  final int voteSlot; // 1..4 — slots 2-4 are AniPlus-only
  final DateTime? votedAt;

  const CommunityVote({
    required this.userId,
    required this.anilistId,
    required this.animeTitle,
    this.animeCover = '',
    required this.dayId,
    required this.voteSlot,
    this.votedAt,
  });

  String get docId => '${userId}_$voteSlot';

  factory CommunityVote.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CommunityVote(
      userId: d['userId'] as String? ?? '',
      anilistId: (d['anilist_id'] as num?)?.toInt() ?? 0,
      animeTitle: d['animeTitle'] as String? ?? '',
      animeCover: d['animeCover'] as String? ?? '',
      dayId: d['dayId'] as String? ?? '',
      voteSlot: (d['voteSlot'] as num?)?.toInt() ?? 0,
      votedAt: (d['votedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'anilist_id': anilistId,
        'animeTitle': animeTitle,
        'animeCover': animeCover,
        'dayId': dayId,
        'voteSlot': voteSlot,
        'votedAt': FieldValue.serverTimestamp(),
      };
}

/// Aggregated per-anime result for one day, at
/// `community_votes/{dayId}/tally/{anilist_id}`. Bumped +1 in the same batch
/// as the vote write (rules only admit +1) until Cloud Functions take over.
class CommunityVoteTally {
  final int anilistId;
  final String animeTitle;
  final String animeCover;
  final int voteCount;
  final String dayId;

  const CommunityVoteTally({
    required this.anilistId,
    required this.animeTitle,
    this.animeCover = '',
    required this.voteCount,
    required this.dayId,
  });

  factory CommunityVoteTally.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CommunityVoteTally(
      anilistId: (d['anilist_id'] as num?)?.toInt() ?? int.tryParse(doc.id) ?? 0,
      animeTitle: d['animeTitle'] as String? ?? '',
      animeCover: d['animeCover'] as String? ?? '',
      voteCount: (d['voteCount'] as num?)?.toInt() ?? 0,
      dayId: d['dayId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'anilist_id': anilistId,
        'animeTitle': animeTitle,
        'animeCover': animeCover,
        'voteCount': voteCount,
        'dayId': dayId,
      };
}
