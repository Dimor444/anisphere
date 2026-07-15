import 'package:cloud_firestore/cloud_firestore.dart';

/// The header slice of the signed-in user's `users/{uid}` profile doc.
///
/// Field names follow what [FollowService.ensureProfile] writes via
/// [UserData.toMap] (displayName / userName / userAvatar / bio / isVerified /
/// createdAt). Distinct from [UserData] — this maps only what the Profile
/// header renders, with safe defaults for missing fields.
class UserProfile {
  final String displayName;

  /// The unique @handle (users/{uid}.userName); '' on pre-handle docs.
  final String userName;
  final String bio;
  final String? avatarUrl;
  final bool isVerified;

  /// Daily login streak (StreakService check-ins); 0 before the first one.
  /// May be stale between opens — display via [StreakService.displayStreak]
  /// with [lastActiveDay], not raw.
  final int currentStreak;

  /// "YYYY-MM-DD" UTC of the last check-in; "" before the first one.
  final String lastActiveDay;
  final DateTime? createdAt;

  const UserProfile({
    required this.displayName,
    this.userName = '',
    this.bio = '',
    this.avatarUrl,
    this.isVerified = false,
    this.currentStreak = 0,
    this.lastActiveDay = '',
    this.createdAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final display = (d['displayName'] as String?)?.trim() ?? '';
    final userName = (d['userName'] as String?)?.trim() ?? '';
    final avatar = (d['userAvatar'] as String?)?.trim() ?? '';
    return UserProfile(
      displayName: display.isNotEmpty ? display : userName,
      userName: userName,
      bio: d['bio'] as String? ?? '',
      avatarUrl: avatar.isEmpty ? null : avatar,
      isVerified: d['isVerified'] as bool? ?? false,
      currentStreak: (d['currentStreak'] as num?)?.toInt() ?? 0,
      lastActiveDay: d['lastActiveDay'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Avatar fallback: first letters of up to two words of [displayName],
  /// uppercased — "Kaze No" → "KN", "Yuki" → "Y", "" → "?".
  String get initials {
    final letters = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return letters.isEmpty ? '?' : letters;
  }
}
