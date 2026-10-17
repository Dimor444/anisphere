import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  /// Which cosmetic is DISPLAYED in each slot, keyed by slot name
  /// ('frame', 'postBorder', 'nameEffect'). Server-owned like the balance:
  /// written only by the equipCosmetic callable, which checks the item is
  /// owned and belongs in that slot.
  ///
  /// Deliberately separate from inventory, which is owner-read only. What
  /// someone OWNS is private; what they DISPLAY is public, and has to be, or
  /// nobody else could render it. A slot missing from the map is unequipped —
  /// there is no "none" sentinel to get wrong.
  ///
  /// A map rather than three flat fields so a fourth slot is not a schema
  /// change: one key stays excluded from the create whitelist instead of
  /// four.
  final Map<String, String> equipped;

  /// The cosmetic displayed in [slot], or null. Unknown slots read as null
  /// rather than throwing — an old client meeting a slot it does not render
  /// should ignore it, not crash.
  String? equippedIn(String slot) => equipped[slot];
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

  /// The handle as the app prints it: "@" and the claimed handle, or until
  /// one is claimed the anifan_ placeholder, which the rules reserve so
  /// nobody else can take it. [nameToShow] only for a profile with no handle.
  String get shownHandle => userName.isNotEmpty ? '@$userName' : nameToShow;

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
    this.equipped = const {},
    this.createdAt,
    this.dnaPinned = const [],
    this.firstAnimeId,
  }) : userNameLower = userNameLower ?? '';

  factory UserData.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      UserData.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// Reads a stored profile. A field holding a value of another type than
  /// [toMap] writes reads as absent — its default — and is logged.
  ///
  /// The rules check the types of displayName, userAvatar, isPrivate and
  /// createdAt only from 2026-10-17; before that a profile could hold text
  /// in isPrivate, and the cast that read it threw. A reader that throws on
  /// one profile fails every list it arrives in — follow suggestions, user
  /// search — so nothing here throws. Unlike a video, a profile is not
  /// dropped whole: it is its owner's name on everything they posted, so a
  /// bad field costs that field, not the person.
  @visibleForTesting
  factory UserData.fromMap(String id, Map<String, dynamic> d) {
    T? read<T>(String key) {
      final v = d[key];
      if (v == null || v is T) return v as T?;
      debugPrint('[UserData] users/$id: $key is ${v.runtimeType}, not $T — read as unset');
      return null;
    }

    // num, not int: a number stored as a double still reads. NaN and the
    // infinities read as unset — toInt() throws on them.
    int? readInt(String key) {
      final v = read<num>(key);
      if (v == null || v.isFinite) return v?.toInt();
      debugPrint('[UserData] users/$id: $key is $v — read as unset');
      return null;
    }

    final name = read<String>('userName') ?? '';
    return UserData(
      id: id,
      userName: name,
      userNameLower: read<String>('userNameLower') ?? name.toLowerCase(),
      displayName: read<String>('displayName') ?? '',
      userAvatar: read<String>('userAvatar') ?? '',
      bio: read<String>('bio') ?? '',
      isVerified: read<bool>('isVerified') ?? false,
      isPlus: read<bool>('isPlus') ?? false,
      countryCode: read<String>('countryCode') ?? '',
      followerCount: readInt('followerCount') ?? 0,
      followingCount: readInt('followingCount') ?? 0,
      postsCount: readInt('postsCount') ?? 0,
      isPrivate: read<bool>('isPrivate') ?? false,
      currentStreak: readInt('currentStreak') ?? 0,
      longestStreak: readInt('longestStreak') ?? 0,
      lastActiveDay: read<String>('lastActiveDay') ?? '',
      aniGold: readInt('aniGold') ?? 0,
      aniGem: readInt('aniGem') ?? 0,
      // Values that are not strings are dropped rather than coerced: a
      // malformed slot should render nothing, never a widget keyed off a
      // number.
      equipped: <String, String>{
        for (final e in (read<Map<Object?, Object?>>('equipped') ?? const {}).entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
      },
      createdAt: read<Timestamp>('createdAt')?.toDate(),
      dnaPinned: read<List<dynamic>>('dnaPinned')
              ?.whereType<num>()
              .where((n) => n.isFinite)
              .map((n) => n.toInt())
              .where((id) => id > 0)
              .toList() ??
          const [],
      firstAnimeId: readInt('firstAnimeId'),
    );
  }

  /// Full Firestore payload (no id — that's the document key). Used on profile
  /// creation; partial updates go through FollowService with explicit fields.
  /// DNA fields (dnaPinned/firstAnimeId) are deliberately absent — the create
  /// rule whitelist doesn't admit them; they're written by AnimeDnaService.
  ///
  /// equipped is absent too, and for the same reason as the balance: the
  /// client may not choose what it displays without the server agreeing it
  /// owns the thing.
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
