import 'package:anisphere/data/models/ani_video.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 10, 13, 12);

  // What uploadVideo stores, with the server's timestamp already resolved.
  Map<String, dynamic> stored() => AniVideoData(
        id: 'v1',
        userId: 'u1',
        userName: 'Alice',
        userAvatar: 'https://cdn.example/a.jpg',
        isVerified: true,
        videoUrl: 'https://pub.example/ani_videos/u1/v1.mp4',
        thumbnailUrl: 'https://pub.example/ani_videos/u1/v1.jpg',
        caption: 'Peak #frieren',
        anilistId: 154587,
        animeTitle: 'Frieren',
        animeCover: 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx154587-qQTzQnEJJ3oB.jpg',
        hashtags: const ['frieren'],
        durationSeconds: 30,
        createdAt: createdAt,
        isSpoiler: true,
      ).toMap();

  group('AniVideoData.fromMap', () {
    test('reads back what toMap writes', () {
      final v = AniVideoData.fromMap('v1', stored());
      expect(v.userName, 'Alice');
      expect(v.isVerified, isTrue);
      expect(v.anilistId, 154587);
      expect(v.hashtags, ['frieren']);
      expect(v.durationSeconds, 30);
      // Timestamp.toDate() is local time: the same instant, another zone.
      expect(v.createdAt!.isAtSameMomentAs(createdAt), isTrue);
      expect(v.isSpoiler, isTrue);
    });

    test('an upload with no anime tagged reads, its nulls as nulls', () {
      final v = AniVideoData.fromMap('v1', stored()
        ..['anilist_id'] = null
        ..['animeTitle'] = null
        ..['animeCover'] = null);
      expect(v.anilistId, isNull);
      expect(v.animeCover, isNull);
    });

    test('absent fields take their defaults', () {
      final v = AniVideoData.fromMap('v1', const {});
      expect(v.caption, '');
      expect(v.hashtags, isEmpty);
      expect(v.likes, 0);
      expect(v.createdAt, isNull);
      expect(v.isSpoiler, isFalse);
    });

    test('a count stored as a double still reads', () {
      expect(AniVideoData.fromMap('v1', stored()..['likes'] = 3.0).likes, 3);
    });

    final wrong = <String, Object>{
      'createdAt': 'zzz',
      'caption': 42,
      'userId': 7,
      'videoUrl': const {'u': 1},
      'isVerified': 'true',
      'isSpoiler': 'yes',
      'anilist_id': '154587',
      'animeTitle': 7,
      'animeCover': 7,
      'hashtags': 'frieren',
      'durationSeconds': '10',
      'likes': double.nan,
      'viewCount': double.infinity,
    };
    for (final MapEntry(:key, :value) in wrong.entries) {
      test('$key holding ${value.runtimeType} ($value) is refused', () {
        expect(() => AniVideoData.fromMap('v1', stored()..[key] = value), throwsFormatException);
      });
    }

    test('a hashtag that is not a string is refused when read, not later', () {
      expect(() => AniVideoData.fromMap('v1', stored()..['hashtags'] = ['ok', 3]), throwsFormatException);
    });

    test('a timestamp is what createdAt holds', () {
      final m = stored();
      expect(m['createdAt'], isA<Timestamp>());
    });
  });
}
