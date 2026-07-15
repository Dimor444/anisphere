import 'user_model.dart';

enum PostMedia { none, image, video }

class PostModel {
  final String id;
  final UserModel author;
  final String text;
  final String translatedText;
  final bool isSpoiler;
  final String? animeTag;
  final PostMedia media;
  final String mediaLabel; // e.g. anime/clip title for the gradient media block
  final int likes;
  final int comments;
  final int shares;
  final DateTime time;
  final bool liked;
  final bool bookmarked;

  const PostModel({
    required this.id,
    required this.author,
    required this.text,
    this.translatedText = '',
    this.isSpoiler = false,
    this.animeTag,
    this.media = PostMedia.none,
    this.mediaLabel = '',
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    required this.time,
    this.liked = false,
    this.bookmarked = false,
  });

  PostModel copyWith({
    int? likes,
    bool? liked,
    bool? bookmarked,
  }) {
    return PostModel(
      id: id,
      author: author,
      text: text,
      translatedText: translatedText,
      isSpoiler: isSpoiler,
      animeTag: animeTag,
      media: media,
      mediaLabel: mediaLabel,
      likes: likes ?? this.likes,
      comments: comments,
      shares: shares,
      time: time,
      liked: liked ?? this.liked,
      bookmarked: bookmarked ?? this.bookmarked,
    );
  }
}
