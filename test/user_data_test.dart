import 'package:anisphere/data/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
