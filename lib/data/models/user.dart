import 'package:cloud_firestore/cloud_firestore.dart';

/// A user's public profile, stored at `users/{userId}`.
///
/// This is the social identity other users can see (profiles, follower lists,
/// suggestions) — distinct from [UserModel], the in-app demo/session model.
/// Counter fields (followerCount/followingCount/postsCount) are denormalized
/// tallies bumped in the same batch as the follow/post write; security rules
/// only admit ±1 counter-only updates until Cloud Functions take over.
class UserData {
  final String id;
  final String userName;

  /// Lowercased copy of [userName], kept for prefix search.
  final String userNameLower;
  final String displayName;
  final String userAvatar;
  final String bio;
  final bool isVerified;

  /// AniPlus subscription — mirrored from the session's subscription status
  /// so security rules can read it (community vote slots 2-4 are Plus-only).
  final bool isPlus;

  /// ISO 3166-1 alpha-2 country code (e.g. "SA", "JP"), auto-detected once
  /// from the device locale ("XX" when the locale has none). Denormalized
  /// onto trueFanScores writes so the Local leaderboard can filter by it.
  final String countryCode;
  final int followerCount;
  final int followingCount;
  final int postsCount;
  final bool isPrivate;

  /// Daily login streak (UTC-day check-ins via StreakService). Rules only
  /// admit +1-or-reset transitions stamped with the server's UTC day.
  final int currentStreak;
  final int longestStreak;

  /// "YYYY-MM-DD" UTC of the last check-in; "" before the first one.
  final String lastActiveDay;

  /// Currency balance. SERVER-OWNED: the rules admit these on no create and
  /// no update path, so the only writer is the Admin SDK. Read here, never
  /// written from the client — which is why [toMap] omits them.
  ///
  /// Absent on every profile written before the fields existed, hence the
  /// `?? 0` in [fromDoc]: no migration is needed, a missing field simply
  /// reads as an empty balance.
  final int aniGold;
  final int aniGem;
  final DateTime? createdAt;

  /// Anime DNA overrides — AniList ids ONLY (no denormalized titles/covers;
  /// everything displayed is fetched live from AniList). [dnaPinned] holds
  /// the owner's pinned card ids (max [maxDnaPinned], empty = fully derived);
  /// [firstAnimeId] is the user-entered "first anime ever" (null = unset).
  final List<int> dnaPinned;
  final int? firstAnimeId;

  static const int maxBioLength = 150;
  static const int maxDnaPinned = 5;

  /// The name surfaces should render: displayName, falling back to the handle.
  String get nameToShow {
    final d = displayName.trim();
    return d.isNotEmpty ? d : userName;
  }

  const UserData({
    required this.id,
    required this.userName,
    String? userNameLower,
    this.displayName = '',
    this.userAvatar = '',
    this.bio = '',
    this.isVerified = false,
    this.isPlus = false,
    this.countryCode = '',
    this.followerCount = 0,
    this.followingCount = 0,
    this.postsCount = 0,
    this.isPrivate = false,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActiveDay = '',
    this.aniGold = 0,
    this.aniGem = 0,
    this.createdAt,
    this.dnaPinned = const [],
    this.firstAnimeId,
  }) : userNameLower = userNameLower ?? '';

  factory UserData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final name = d['userName'] as String? ?? '';
    return UserData(
      id: doc.id,
      userName: name,
      userNameLower: d['userNameLower'] as String? ?? name.toLowerCase(),
      displayName: d['displayName'] as String? ?? '',
      userAvatar: d['userAvatar'] as String? ?? '',
      bio: d['bio'] as String? ?? '',
      isVerified: d['isVerified'] as bool? ?? false,
      isPlus: d['isPlus'] as bool? ?? false,
      countryCode: d['countryCode'] as String? ?? '',
      followerCount: (d['followerCount'] as num?)?.toInt() ?? 0,
      followingCount: (d['followingCount'] as num?)?.toInt() ?? 0,
      postsCount: (d['postsCount'] as num?)?.toInt() ?? 0,
      isPrivate: d['isPrivate'] as bool? ?? false,
      currentStreak: (d['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (d['longestStreak'] as num?)?.toInt() ?? 0,
      lastActiveDay: d['lastActiveDay'] as String? ?? '',
      aniGold: (d['aniGold'] as num?)?.toInt() ?? 0,
      aniGem: (d['aniGem'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      dnaPinned: (d['dnaPinned'] as List<dynamic>?)
              ?.whereType<num>()
              .map((n) => n.toInt())
              .where((id) => id > 0)
              .toList() ??
          const [],
      firstAnimeId: (d['firstAnimeId'] as num?)?.toInt(),
    );
  }

  /// Full Firestore payload (no id — that's the document key). Used on profile
  /// creation; partial updates go through FollowService with explicit fields.
  /// DNA fields (dnaPinned/firstAnimeId) are deliberately absent — the create
  /// rule whitelist doesn't admit them; they're written by AnimeDnaService.
  ///
  /// aniGold/aniGem are absent for the same reason and a stronger one: they
  /// are spendable and server-owned. Emitting them would make every profile
  /// create carry a balance the client chose, and the create rule would
  /// reject the write outright — so their absence here is load-bearing, not
  /// tidiness. Nothing client-side may ever put them in a payload.
  Map<String, dynamic> toMap() => {
        'userId': id,
        'userName': userName,
        'userNameLower': userNameLower.isNotEmpty ? userNameLower : userName.toLowerCase(),
        'displayName': displayName,
        'userAvatar': userAvatar,
        'bio': bio.length > maxBioLength ? bio.substring(0, maxBioLength) : bio,
        'isVerified': isVerified,
        'isPlus': isPlus,
        'countryCode': countryCode,
        'followerCount': followerCount,
        'followingCount': followingCount,
        'postsCount': postsCount,
        'isPrivate': isPrivate,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastActiveDay': lastActiveDay,
        'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      };
}
