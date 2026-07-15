import 'package:anisphere/data/models/post.dart';
import 'package:anisphere/data/models/post_model.dart';
import 'package:anisphere/data/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PostData.extractHashtags', () {
    test('finds ASCII, unicode and underscored tags, lowercased + deduped', () {
      expect(
        PostData.extractHashtags('Loved #Frieren and #jujutsu_kaisen! #FRIEREN #呪術廻戦'),
        ['frieren', 'jujutsu_kaisen', '呪術廻戦'],
      );
    });

    test('ignores text without tags and bare #', () {
      expect(PostData.extractHashtags('no tags here # not-a-tag'), isEmpty);
    });
  });

  group('PostData.toMap', () {
    test('serializes all fields and uses server timestamps when unset', () {
      const post = PostData(
        id: 'p1',
        userId: 'u1',
        userName: 'Yuki',
        content: 'Peak fiction #frieren',
        anilistId: 154587,
        animeTitle: 'Frieren',
        hashtags: ['frieren'],
        isSpoiler: true,
      );
      final map = post.toMap();
      expect(map['userId'], 'u1');
      expect(map['content'], 'Peak fiction #frieren');
      expect(map['anilist_id'], 154587);
      expect(map['hashtags'], ['frieren']);
      expect(map['isSpoiler'], true);
      expect(map['likes'], 0);
      expect(map['createdAt'], isA<FieldValue>());
      expect(map.containsKey('id'), isFalse);
    });

    test('round-trips explicit timestamps', () {
      final t = DateTime(2026, 7, 5, 12);
      final map = PostData(id: 'p', userId: 'u', userName: 'n', content: 'c', createdAt: t).toMap();
      expect((map['createdAt'] as Timestamp).toDate(), t);
    });
  });

  group('PostData image urls', () {
    test('toMap writes imageUrls and no legacy imageUrl key', () {
      const post = PostData(
          id: 'p', userId: 'u', userName: 'n', content: 'c', imageUrls: ['a', 'b']);
      final map = post.toMap();
      expect(map['imageUrls'], ['a', 'b']);
      expect(map.containsKey('imageUrl'), isFalse);
    });

    test('imageUrlsFromMap prefers imageUrls over the legacy field', () {
      expect(
        PostData.imageUrlsFromMap({'imageUrls': ['a', 'b'], 'imageUrl': 'old'}),
        ['a', 'b'],
      );
    });

    test('imageUrlsFromMap folds a legacy single imageUrl into the list', () {
      expect(PostData.imageUrlsFromMap({'imageUrl': 'old'}), ['old']);
      expect(PostData.imageUrlsFromMap({'imageUrls': [], 'imageUrl': 'old'}), ['old']);
    });

    test('imageUrlsFromMap treats missing/empty fields as a text-only post', () {
      expect(PostData.imageUrlsFromMap({}), isEmpty);
      expect(PostData.imageUrlsFromMap({'imageUrl': ''}), isEmpty);
      expect(PostData.imageUrlsFromMap({'imageUrls': []}), isEmpty);
    });
  });

  test('PostData.fromSample maps the demo model and marks it local', () {
    final sample = PostModel(
      id: 's1',
      author: const UserModel(id: 'u_s', username: 'Sakura', isVerified: true),
      text: 'Hot take #chainsawman',
      likes: 12,
      comments: 3,
      time: DateTime(2026, 1, 1),
      isSpoiler: true,
    );
    final post = PostData.fromSample(sample);
    expect(post.isLocal, isTrue);
    expect(post.userName, 'Sakura');
    expect(post.isVerified, isTrue);
    expect(post.hashtags, ['chainsawman']);
    expect(post.likes, 12);
    expect(post.commentsCount, 3);
    expect(post.isSpoiler, isTrue);
  });
}
