import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      UserProfile.fromMap(doc.id, doc.data() ?? const <String, dynamic>{});

  /// A field of another type than [UserData.toMap] writes reads as absent
  /// and is logged, as in [UserData.fromMap] and for the same reason: the
  /// profile header must not fail on a profile stored before the rules
  /// checked types.
  @visibleForTesting
  factory UserProfile.fromMap(String id, Map<String, dynamic> d) {
    T? read<T>(String key) {
      final v = d[key];
      if (v == null || v is T) return v as T?;
      debugPrint('[UserProfile] users/$id: $key is ${v.runtimeType}, not $T — read as unset');
      return null;
    }

    final streak = read<num>('currentStreak');
    final display = read<String>('displayName')?.trim() ?? '';
    final userName = read<String>('userName')?.trim() ?? '';
    final avatar = read<String>('userAvatar')?.trim() ?? '';
    return UserProfile(
      displayName: display.isNotEmpty ? display : userName,
      userName: userName,
      bio: read<String>('bio') ?? '',
      avatarUrl: avatar.isEmpty ? null : avatar,
      isVerified: read<bool>('isVerified') ?? false,
      currentStreak: streak != null && streak.isFinite ? streak.toInt() : 0,
      lastActiveDay: read<String>('lastActiveDay') ?? '',
      createdAt: read<Timestamp>('createdAt')?.toDate(),
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
