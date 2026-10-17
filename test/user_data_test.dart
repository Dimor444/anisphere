import 'package:anisphere/data/models/user.dart';
import 'package:anisphere/data/models/user_profile.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserData.shownHandle', () {
    test('the claimed handle, with an @', () {
      expect(const UserData(id: 'u', userName: 'mira_k', displayName: 'Mira').shownHandle, '@mira_k');
    });
    test("an unclaimed guest's placeholder handle, with an @", () {
      expect(const UserData(id: 'u', userName: 'anifan_ab12cd', displayName: 'Anime Fan').shownHandle,
          '@anifan_ab12cd');
    });
    test('the display name only when there is no handle at all', () {
      expect(const UserData(id: 'u', userName: '', displayName: 'Mira').shownHandle, 'Mira');
    });
  });

  group('UserData.toMap', () {
    test('serializes profile fields, derives userNameLower, zeroes counters', () {
      const user = UserData(id: 'u1', userName: 'KazeNoYuki', bio: 'hi', isVerified: true);
      final map = user.toMap();
      expect(map['userId'], 'u1');
      expect(map['userName'], 'KazeNoYuki');
      expect(map['userNameLower'], 'kazenoyuki');
      expect(map['bio'], 'hi');
      expect(map['isVerified'], true);
      expect(map['followerCount'], 0);
      expect(map['followingCount'], 0);
      expect(map['postsCount'], 0);
      expect(map['isPrivate'], false);
      expect(map['createdAt'], isA<FieldValue>());
      expect(map.containsKey('id'), isFalse);
    });

    test('caps bio at 150 chars', () {
      final map = UserData(id: 'u', userName: 'n', bio: 'x' * 200).toMap();
      expect((map['bio'] as String).length, UserData.maxBioLength);
    });
  });
  group('UserData.fromMap', () {
    test('reads what toMap writes', () {
      final u = UserData.fromMap('u1', {
        ...const UserData(id: 'u1', userName: 'mira_k', displayName: 'Mira', isPrivate: true).toMap(),
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(0),
      });
      expect(u.userName, 'mira_k');
      expect(u.displayName, 'Mira');
      expect(u.isPrivate, isTrue);
      expect(u.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('a field of another type reads as unset, and the rest still reads', () {
      final u = UserData.fromMap('u1', {
        'userName': 'mira_k',
        'displayName': 42,
        'userAvatar': {'url': 'x'},
        'bio': 'still here',
        'isPrivate': 'yes',
        'createdAt': '2026-10-17',
        'followerCount': '12',
        'dnaPinned': 'frieren',
        'equipped': ['frame'],
      });
      expect(u.userName, 'mira_k');
      expect(u.bio, 'still here');
      expect(u.displayName, '');
      expect(u.userAvatar, '');
      expect(u.isPrivate, isFalse);
      expect(u.createdAt, isNull);
      expect(u.followerCount, 0);
      expect(u.dnaPinned, isEmpty);
      expect(u.equipped, isEmpty);
    });

    test('a number stored as a double reads; NaN and infinity read as unset', () {
      final u = UserData.fromMap('u1', {
        'followerCount': 3.0,
        'postsCount': double.nan,
        'currentStreak': double.infinity,
        'dnaPinned': [21, double.nan, 154587.0],
        'firstAnimeId': double.nan,
      });
      expect(u.followerCount, 3);
      expect(u.postsCount, 0);
      expect(u.currentStreak, 0);
      expect(u.dnaPinned, [21, 154587]);
      expect(u.firstAnimeId, isNull);
    });
  });

  group('UserProfile.fromMap', () {
    test('a field of another type reads as unset, and the rest still reads', () {
      final p = UserProfile.fromMap('u1', {
        'userName': 'mira_k',
        'displayName': 42,
        'userAvatar': ['x'],
        'bio': 'still here',
        'isVerified': 'yes',
        'currentStreak': double.nan,
        'createdAt': '2026-10-17',
      });
      expect(p.displayName, 'mira_k');
      expect(p.avatarUrl, isNull);
      expect(p.bio, 'still here');
      expect(p.isVerified, isFalse);
      expect(p.currentStreak, 0);
      expect(p.createdAt, isNull);
    });
  });
}
