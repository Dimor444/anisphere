import 'package:flutter/material.dart';
import 'models/user_model.dart';
import 'models/anime_model.dart';
import 'models/post_model.dart';
import 'models/message_model.dart';
import 'models/card_model.dart';

/// All demo content for AniSphere. Real anime titles, no lorem ipsum,
/// no grey placeholders — gradients + emoji carry the visuals.
class SampleData {
  SampleData._();

  // ─────────────────────────────────────────── USERS
  static const UserModel mainUser = UserModel(
    id: 'u_me',
    username: 'KazeNoYuki',
    displayName: 'Yuki',
    bio: 'Chasing every season since 2014 ✨ | Frieren changed me | JJK apologist',
    level: UserLevel.otakuElite,
    isVerified: true,
    isPlusUser: true,
    watchedAnime: 347,
    episodes: 4821,
    hours: 1203,
    following: 892,
    followers: 2341,
    streak: 42,
    memberSince: 'March 2024',
    trueFanRank: 847,
    aniGold: 1240,
    aniGem: 85,
    topAnime: ['Frieren', 'Vinland Saga', 'Hunter x Hunter'],
    genres: ['Adventure', 'Drama', 'Dark Fantasy', 'Seinen', 'Action'],
    firstAnime: 'Naruto (2007)',
    country: '🇯🇵',
  );

  static const UserModel sakura = UserModel(
    id: 'u_sakura',
    username: 'SakuraBlade',
    level: UserLevel.weebGod,
    isVerified: true,
    streak: 98,
    followers: 18400,
    following: 312,
    trueFanRank: 12,
    country: '🇯🇵',
    topAnime: ['Demon Slayer', 'Jujutsu Kaisen', 'Chainsaw Man'],
    isFollowedByMe: true,
  );

  static const UserModel ryuu = UserModel(
    id: 'u_ryuu',
    username: 'RyuuSenpai',
    level: UserLevel.otaku,
    streak: 15,
    followers: 980,
    following: 540,
    trueFanRank: 2103,
    country: '🇺🇸',
    topAnime: ['One Piece', 'Bleach', 'Dragon Ball Z'],
    isFollowedByMe: true,
  );

  static const UserModel aoi = UserModel(
    id: 'u_aoi',
    username: 'AoiHanabi',
    level: UserLevel.weeb,
    streak: 7,
    followers: 4200,
    following: 210,
    trueFanRank: 540,
    country: '🇧🇷',
    topAnime: ['Spy x Family', 'Frieren', 'Solo Leveling'],
    isFollowedByMe: true,
  );

  static const UserModel kenji = UserModel(
    id: 'u_kenji',
    username: 'KenjiZero',
    level: UserLevel.otakuElite,
    isVerified: true,
    streak: 61,
    followers: 9100,
    trueFanRank: 88,
    country: '🇰🇷',
    topAnime: ['Re:Zero', 'Mushoku Tensei', 'Frieren'],
  );

  static const UserModel mei = UserModel(
    id: 'u_mei',
    username: 'MeiNoSora',
    level: UserLevel.otaku,
    streak: 23,
    followers: 1500,
    trueFanRank: 1320,
    country: '🇸🇦',
    topAnime: ['Attack on Titan', 'Vinland Saga', 'Tokyo Ghoul'],
  );

  static List<UserModel> get friends => [sakura, ryuu, aoi];
  static List<UserModel> get people => [sakura, ryuu, aoi, kenji, mei];

  // ─────────────────────────────────────────── ANIME (20)
  static const List<AnimeModel> animeList = [
    AnimeModel(id: 'an1', title: 'Naruto', japaneseTitle: 'ナルト', studio: 'Pierrot', genre: 'Shonen', genres: ['Action', 'Adventure'], year: 2002, episodes: 220, score: 8.4, ratingCount: 412000, status: 'Finished', emoji: '🍥'),
    AnimeModel(id: 'an2', title: 'One Piece', japaneseTitle: 'ワンピース', studio: 'Toei', genre: 'Shonen', genres: ['Adventure', 'Comedy'], year: 1999, episodes: 1100, score: 9.1, ratingCount: 720000, status: 'Airing', emoji: '🏴‍☠️', watchingNow: 41200),
    AnimeModel(id: 'an3', title: 'Attack on Titan', japaneseTitle: '進撃の巨人', studio: 'Wit / MAPPA', genre: 'Dark Fantasy', genres: ['Action', 'Drama'], year: 2013, episodes: 89, score: 9.2, ratingCount: 980000, status: 'Finished', emoji: '⚔️'),
    AnimeModel(id: 'an4', title: 'Demon Slayer', japaneseTitle: '鬼滅の刃', studio: 'ufotable', genre: 'Shonen', genres: ['Action', 'Supernatural'], year: 2019, episodes: 55, score: 8.7, ratingCount: 660000, status: 'Airing', emoji: '🗡️', watchingNow: 33100),
    AnimeModel(id: 'an5', title: 'Frieren', japaneseTitle: '葬送のフリーレン', studio: 'Madhouse', genre: 'Adventure', genres: ['Fantasy', 'Drama'], year: 2023, episodes: 28, score: 9.4, ratingCount: 290000, status: 'Airing', emoji: '🧝‍♀️', watchingNow: 58900),
    AnimeModel(id: 'an6', title: 'Hunter x Hunter', japaneseTitle: 'ハンター×ハンター', studio: 'Madhouse', genre: 'Shonen', genres: ['Adventure', 'Action'], year: 2011, episodes: 148, score: 9.3, ratingCount: 540000, status: 'Finished', emoji: '🎯'),
    AnimeModel(id: 'an7', title: 'Jujutsu Kaisen', japaneseTitle: '呪術廻戦', studio: 'MAPPA', genre: 'Shonen', genres: ['Action', 'Supernatural'], year: 2020, episodes: 47, score: 8.8, ratingCount: 510000, status: 'Airing', emoji: '👊', watchingNow: 39800),
    AnimeModel(id: 'an8', title: 'Bleach', japaneseTitle: 'ブリーチ', studio: 'Pierrot', genre: 'Shonen', genres: ['Action', 'Supernatural'], year: 2004, episodes: 396, score: 8.5, ratingCount: 320000, status: 'Airing', emoji: '☠️'),
    AnimeModel(id: 'an9', title: 'Fullmetal Alchemist: Brotherhood', japaneseTitle: '鋼の錬金術師', studio: 'Bones', genre: 'Adventure', genres: ['Action', 'Drama'], year: 2009, episodes: 64, score: 9.5, ratingCount: 710000, status: 'Finished', emoji: '⚗️'),
    AnimeModel(id: 'an10', title: 'Chainsaw Man', japaneseTitle: 'チェンソーマン', studio: 'MAPPA', genre: 'Seinen', genres: ['Action', 'Horror'], year: 2022, episodes: 12, score: 8.6, ratingCount: 380000, status: 'Finished', emoji: '🪚'),
    AnimeModel(id: 'an11', title: 'Solo Leveling', japaneseTitle: '俺だけレベルアップな件', studio: 'A-1 Pictures', genre: 'Action', genres: ['Action', 'Fantasy'], year: 2024, episodes: 25, score: 8.5, ratingCount: 270000, status: 'Airing', emoji: '⚡', watchingNow: 47600),
    AnimeModel(id: 'an12', title: 'Vinland Saga', japaneseTitle: 'ヴィンランド・サガ', studio: 'Wit / MAPPA', genre: 'Seinen', genres: ['Action', 'Drama'], year: 2019, episodes: 48, score: 9.0, ratingCount: 240000, status: 'Finished', emoji: '🪓'),
    AnimeModel(id: 'an13', title: 'Re:Zero', japaneseTitle: 'Re:ゼロ', studio: 'White Fox', genre: 'Isekai', genres: ['Drama', 'Fantasy'], year: 2016, episodes: 50, score: 8.7, ratingCount: 330000, status: 'Airing', emoji: '🔁'),
    AnimeModel(id: 'an14', title: 'Spy x Family', japaneseTitle: 'スパイファミリー', studio: 'Wit / CloverWorks', genre: 'Comedy', genres: ['Comedy', 'Action'], year: 2022, episodes: 37, score: 8.6, ratingCount: 360000, status: 'Airing', emoji: '🕵️', watchingNow: 28700),
    AnimeModel(id: 'an15', title: 'One Punch Man', japaneseTitle: 'ワンパンマン', studio: 'Madhouse', genre: 'Action', genres: ['Action', 'Comedy'], year: 2015, episodes: 24, score: 8.5, ratingCount: 470000, status: 'Airing', emoji: '👊'),
    AnimeModel(id: 'an16', title: 'Tokyo Ghoul', japaneseTitle: '東京喰種', studio: 'Pierrot', genre: 'Dark Fantasy', genres: ['Horror', 'Action'], year: 2014, episodes: 48, score: 7.8, ratingCount: 410000, status: 'Finished', emoji: '🩸'),
    AnimeModel(id: 'an17', title: 'Dragon Ball Z', japaneseTitle: 'ドラゴンボールZ', studio: 'Toei', genre: 'Shonen', genres: ['Action', 'Adventure'], year: 1989, episodes: 291, score: 8.6, ratingCount: 520000, status: 'Finished', emoji: '🐉'),
    AnimeModel(id: 'an18', title: 'Blue Lock', japaneseTitle: 'ブルーロック', studio: '8bit', genre: 'Sports', genres: ['Sports', 'Drama'], year: 2022, episodes: 38, score: 8.3, ratingCount: 190000, status: 'Airing', emoji: '⚽', watchingNow: 21400),
    AnimeModel(id: 'an19', title: 'Dandadan', japaneseTitle: 'ダンダダン', studio: 'Science SARU', genre: 'Supernatural', genres: ['Action', 'Comedy'], year: 2024, episodes: 12, score: 8.7, ratingCount: 150000, status: 'Airing', emoji: '👽', watchingNow: 35200),
    AnimeModel(id: 'an20', title: 'Mushoku Tensei', japaneseTitle: '無職転生', studio: 'Studio Bind', genre: 'Isekai', genres: ['Fantasy', 'Adventure'], year: 2021, episodes: 47, score: 8.6, ratingCount: 210000, status: 'Airing', emoji: '🪄'),
    AnimeModel(id: 'an21', title: 'My Hero Academia', japaneseTitle: '僕のヒーローアカデミア', studio: 'Bones', genre: 'Shonen', genres: ['Action', 'Superhero'], year: 2016, episodes: 159, score: 7.8, ratingCount: 540000, status: 'Finished', emoji: '💥'),
    AnimeModel(id: 'an22', title: 'Death Note', japaneseTitle: 'デスノート', studio: 'Madhouse', genre: 'Thriller', genres: ['Mystery', 'Supernatural'], year: 2006, episodes: 37, score: 8.5, ratingCount: 690000, status: 'Finished', emoji: '📓'),
    AnimeModel(id: 'an23', title: 'Tokyo Revengers', japaneseTitle: '東京卍リベンジャーズ', studio: 'Liden Films', genre: 'Action', genres: ['Action', 'Drama'], year: 2021, episodes: 50, score: 7.5, ratingCount: 180000, status: 'Finished', emoji: '⏳'),
    AnimeModel(id: 'an24', title: 'Mob Psycho 100', japaneseTitle: 'モブサイコ100', studio: 'Bones', genre: 'Supernatural', genres: ['Action', 'Comedy'], year: 2016, episodes: 37, score: 8.6, ratingCount: 250000, status: 'Finished', emoji: '🌀'),
    AnimeModel(id: 'an25', title: 'Code Geass', japaneseTitle: 'コードギアス', studio: 'Sunrise', genre: 'Mecha', genres: ['Mecha', 'Drama'], year: 2006, episodes: 50, score: 8.7, ratingCount: 380000, status: 'Finished', emoji: '♟️'),
    AnimeModel(id: 'an26', title: 'Steins;Gate', japaneseTitle: 'シュタインズ・ゲート', studio: 'White Fox', genre: 'Sci-Fi', genres: ['Sci-Fi', 'Thriller'], year: 2011, episodes: 24, score: 9.1, ratingCount: 470000, status: 'Finished', emoji: '⏰'),
    AnimeModel(id: 'an27', title: 'Black Clover', japaneseTitle: 'ブラッククローバー', studio: 'Pierrot', genre: 'Shonen', genres: ['Action', 'Fantasy'], year: 2017, episodes: 170, score: 8.2, ratingCount: 200000, status: 'Finished', emoji: '🍀'),
    AnimeModel(id: 'an28', title: 'Fairy Tail', japaneseTitle: 'フェアリーテイル', studio: 'A-1 Pictures', genre: 'Fantasy', genres: ['Action', 'Adventure'], year: 2009, episodes: 328, score: 7.6, ratingCount: 230000, status: 'Finished', emoji: '🧚'),
    AnimeModel(id: 'an29', title: 'Sword Art Online', japaneseTitle: 'ソードアート・オンライン', studio: 'A-1 Pictures', genre: 'Isekai', genres: ['Action', 'Fantasy'], year: 2012, episodes: 96, score: 7.0, ratingCount: 360000, status: 'Finished', emoji: '🗡️'),
    AnimeModel(id: 'an30', title: 'Haikyuu', japaneseTitle: 'ハイキュー!!', studio: 'Production I.G', genre: 'Sports', genres: ['Sports', 'Drama'], year: 2014, episodes: 85, score: 8.7, ratingCount: 270000, status: 'Finished', emoji: '🏐'),
  ];

  static AnimeModel animeByTitle(String title) =>
      animeList.firstWhere((a) => a.title == title, orElse: () => animeList.first);

  static AnimeModel animeById(String id) =>
      animeList.firstWhere((a) => a.id == id, orElse: () => animeList.first);

  static const List<String> trendingThisSeason = [
    'Frieren', 'Solo Leveling S3', 'Dandadan S2', 'Blue Box',
    'Sakamoto Days', 'Medalist', 'Lazarus',
  ];

  // ─────────────────────────────────────────── POSTS (5)
  static List<PostModel> get posts => [
        PostModel(
          id: 'p1',
          author: sakura,
          text: 'Episode 18 of Frieren genuinely made me cry. The way they handle the passage of time and grief is unmatched in modern anime. 🥹',
          translatedText: '[Translated] La forma en que Frieren maneja el tiempo y el duelo no tiene comparación. 🥹',
          animeTag: 'Frieren',
          media: PostMedia.image,
          mediaLabel: 'Frieren',
          likes: 4823,
          comments: 412,
          shares: 188,
          time: _ago(const Duration(minutes: 24)),
          liked: true,
        ),
        PostModel(
          id: 'p2',
          author: kenji,
          text: 'HOT TAKE: the Shibuya arc is the best animated sequence MAPPA has ever produced. Fight me. 🔥',
          translatedText: '[Translated] 渋谷事変はMAPPA史上最高の作画だ。異論は認めない。🔥',
          animeTag: 'Jujutsu Kaisen',
          likes: 2210,
          comments: 903,
          shares: 67,
          time: _ago(const Duration(hours: 2)),
        ),
        PostModel(
          id: 'p3',
          author: aoi,
          text: 'Gojo… I can\'t believe what just happened. I am NOT okay after this chapter adaptation. 💀',
          isSpoiler: true,
          animeTag: 'Jujutsu Kaisen',
          media: PostMedia.video,
          mediaLabel: 'JJK • Clip',
          likes: 8741,
          comments: 2100,
          shares: 540,
          time: _ago(const Duration(hours: 5)),
        ),
        PostModel(
          id: 'p4',
          author: ryuu,
          text: 'One Piece hitting 1100 episodes and STILL peak. Egghead arc is cooking. Luffy vs the world never gets old 🏴‍☠️',
          animeTag: 'One Piece',
          media: PostMedia.image,
          mediaLabel: 'One Piece',
          likes: 6312,
          comments: 780,
          shares: 233,
          time: _ago(const Duration(hours: 9)),
        ),
        PostModel(
          id: 'p5',
          author: mei,
          text: 'Solo Leveling S2 animation is INSANE. A-1 understood the assignment. Shadow army go brrr ⚡',
          translatedText: '[Translated] رسوم Solo Leveling الموسم الثاني مذهلة! ⚡',
          animeTag: 'Solo Leveling',
          media: PostMedia.image,
          mediaLabel: 'Solo Leveling',
          likes: 5190,
          comments: 611,
          shares: 301,
          time: _ago(const Duration(hours: 14)),
        ),
      ];

  // ─────────────────────────────────────────── ANIMATCH
  static List<AniMatch> get matches => [
        const AniMatch(sakura, 94, ['Frieren', 'JJK', 'Chainsaw Man', 'Vinland']),
        const AniMatch(kenji, 91, ['Re:Zero', 'Frieren', 'Mushoku Tensei']),
        const AniMatch(aoi, 88, ['Spy x Family', 'Frieren', 'Solo Leveling']),
        const AniMatch(mei, 83, ['AoT', 'Vinland Saga', 'Tokyo Ghoul']),
        const AniMatch(ryuu, 79, ['One Piece', 'Bleach', 'DBZ']),
      ];

  // ─────────────────────────────────────────── NEWS
  static List<NewsItem> get news => [
        NewsItem('Frieren Season 2 Officially Confirmed for 2026', 'Crunchyroll', 'Season 2', _ago(const Duration(hours: 3))),
        NewsItem('Chainsaw Man: Reze Arc Movie Drops First Trailer', 'MAPPA', 'Movie', _ago(const Duration(hours: 6))),
        NewsItem('Demon Slayer × Solo Leveling Collab Event Announced', 'AniSphere', 'Collab', _ago(const Duration(hours: 11))),
        NewsItem('Jujutsu Kaisen S3 "Culling Game" Visual Revealed', 'Shueisha', 'Announcement', _ago(const Duration(days: 1))),
        NewsItem('One Piece Egghead Finale Breaks Streaming Records', 'Toei', 'Announcement', _ago(const Duration(days: 2))),
      ];

  // ─────────────────────────────────────────── CHART (Top anime)
  static List<ChartEntry> get chart => [
        const ChartEntry(1, 'Fullmetal Alchemist: Brotherhood', 9.52, 710000, 0),
        const ChartEntry(2, 'Frieren', 9.41, 290000, 2),
        const ChartEntry(3, 'Attack on Titan', 9.24, 980000, -1),
        const ChartEntry(4, 'Hunter x Hunter', 9.23, 540000, 1),
        const ChartEntry(5, 'One Piece', 9.10, 720000, -2),
        const ChartEntry(6, 'Vinland Saga', 9.01, 240000, 0),
        const ChartEntry(7, 'Jujutsu Kaisen', 8.84, 510000, 3),
        const ChartEntry(8, 'Re:Zero', 8.72, 330000, -1),
        const ChartEntry(9, 'Demon Slayer', 8.70, 660000, 0),
        const ChartEntry(10, 'Chainsaw Man', 8.61, 380000, 1),
      ];

  // ─────────────────────────────────────────── DMs
  static List<Conversation> get conversations => [
        Conversation(
          id: 'c1',
          user: sakura,
          lastMessage: 'did you watch the new ep?? 😭',
          lastTime: _ago(const Duration(minutes: 8)),
          unread: 2,
          streak: 23,
          streakAtRisk: true,
          isOnline: true,
          messages: [
            MessageModel(id: 'm1', isMe: false, text: 'yooo are you online', time: _ago(const Duration(minutes: 18))),
            MessageModel(id: 'm2', isMe: true, text: 'yeah just finished Frieren ep 18', time: _ago(const Duration(minutes: 16))),
            MessageModel(id: 'm3', isMe: false, text: 'CRYING. the mirror lotus scene', time: _ago(const Duration(minutes: 15))),
            MessageModel(id: 'm4', isMe: false, kind: MessageKind.aniVideo, videoTitle: 'Frieren — Mirror Lotus AMV', videoTag: 'Frieren', time: _ago(const Duration(minutes: 14))),
            MessageModel(id: 'm5', isMe: true, text: 'okay that AMV goes hard 🔥', time: _ago(const Duration(minutes: 12))),
            MessageModel(id: 'm6', isMe: false, text: 'did you watch the new ep?? 😭', time: _ago(const Duration(minutes: 8)), read: false),
          ],
        ),
        Conversation(
          id: 'c2',
          user: ryuu,
          lastMessage: 'One Piece never misses fr',
          lastTime: _ago(const Duration(hours: 1)),
          streak: 15,
          isOnline: true,
          messages: [
            MessageModel(id: 'm7', isMe: false, text: 'Egghead arc cooking', time: _ago(const Duration(hours: 1, minutes: 4))),
            MessageModel(id: 'm8', isMe: true, text: 'peak fiction honestly', time: _ago(const Duration(hours: 1, minutes: 2))),
            MessageModel(id: 'm9', isMe: false, text: 'One Piece never misses fr', time: _ago(const Duration(hours: 1))),
          ],
        ),
        Conversation(
          id: 'c3',
          user: aoi,
          lastMessage: 'sent you a card 🎴',
          lastTime: _ago(const Duration(hours: 4)),
          streak: 7,
          unread: 1,
          messages: [
            MessageModel(id: 'm10', isMe: false, text: 'pulled a legendary Gojo card!!', time: _ago(const Duration(hours: 4, minutes: 2))),
            MessageModel(id: 'm11', isMe: false, text: 'sent you a card 🎴', time: _ago(const Duration(hours: 4)), read: false),
          ],
        ),
      ];

  // ─────────────────────────────────────────── NOTIFICATIONS
  static List<NotificationItem> get notifications => [
        NotificationItem(NotifType.follow, sakura, 'started following you', _ago(const Duration(minutes: 5))),
        NotificationItem(NotifType.newEpisode, null, 'Frieren Episode 28 is out! 🎌', _ago(const Duration(minutes: 30)), anime: 'Frieren'),
        NotificationItem(NotifType.streakWarning, null, 'Your streak ends in 1 hour! ⚠️', _ago(const Duration(minutes: 42))),
        NotificationItem(NotifType.like, kenji, 'liked your post', _ago(const Duration(hours: 1))),
        NotificationItem(NotifType.streakBonus, null, '+100🟡 for your 7-day streak! 🔥', _ago(const Duration(hours: 2))),
        NotificationItem(NotifType.friend, aoi, 'is now your friend! 🤝', _ago(const Duration(hours: 3))),
        NotificationItem(NotifType.smart, null, 'On this day last year, you completed Attack on Titan! 📅', _ago(const Duration(hours: 5)), anime: 'Attack on Titan'),
        NotificationItem(NotifType.smart, ryuu, 'reached the same episode as you in One Piece 👀', _ago(const Duration(hours: 8)), anime: 'One Piece'),
        NotificationItem(NotifType.smart, null, 'Dandadan is trending in your region 📈', _ago(const Duration(hours: 12)), anime: 'Dandadan'),
        NotificationItem(NotifType.trueFan, mei, 'beat your True Fan record on Demon Slayer! 🏆', _ago(const Duration(days: 1))),
      ];

  // ─────────────────────────────────────────── ACHIEVEMENTS
  static List<Achievement> get achievements => [
        const Achievement('First Steps', '🎬', 'Watch your first anime', 'Watching', true, 1, '2014'),
        const Achievement('Binge Master', '🍿', 'Watch 12 episodes in a day', 'Watching', true, 1, 'Mar 2024'),
        const Achievement('Century', '💯', 'Complete 100 anime', 'Watching', true, 1, 'Jan 2025'),
        const Achievement('Social Butterfly', '🦋', 'Reach 1,000 followers', 'Social', true, 1, 'Nov 2024'),
        const Achievement('Streak Legend', '🔥', 'Maintain a 30-day streak', 'Social', true, 1, 'May 2025'),
        const Achievement('True Fan', '🎯', 'Score 10/10 on a True Fan quiz', 'Competitive', true, 1, 'Feb 2025'),
        const Achievement('Top 10 True Fan', '🏆', 'Reach top 10 worldwide', 'Competitive', false, 0.42, '#847 → #10'),
        const Achievement('Creator', '🎨', 'Post 50 Ani Videos', 'Creator', false, 0.36, '18 / 50'),
        const Achievement('Critic', '✍️', 'Write 20 reviews', 'Creator', false, 0.65, '13 / 20'),
        const Achievement('Gacha God', '🎴', 'Pull a Legendary card', 'Competitive', true, 1, 'Apr 2025'),
        const Achievement('Polyglot', '🌍', 'Use the app in 3 languages', 'Social', false, 0.66, '2 / 3'),
        const Achievement('Night Owl', '🦉', 'Watch after 2AM 50 times', 'Watching', true, 1, 'Dec 2024'),
      ];

  // ─────────────────────────────────────────── STORE ITEMS
  static const List<StoreItem> storeItems = [
    StoreItem('Cherry Blossom Frame', 'Profile frame', 200, '🌸', [Color(0xFFF472B6), Color(0xFF8B5CF6)]),
    StoreItem('Demon Slayer Emotions', 'Chat sticker pack', 150, '🗡️', [Color(0xFF14B8A6), Color(0xFFEC4899)]),
    StoreItem('Rainbow Shimmer', 'Username effect', 300, '🌈', [Color(0xFF8B5CF6), Color(0xFF22D3EE)]),
    StoreItem('Gold Elite', 'Post border frame', 250, '✨', [Color(0xFFF59E0B), Color(0xFFB45309)]),
    StoreItem('Verification ✓', 'Account verification', 444, '✅', [Color(0xFF3B82F6), Color(0xFF22D3EE)]),
    StoreItem('Streak Restore', 'Revive a lost streak', 50, '🔥', [Color(0xFFFB7185), Color(0xFFEF4444)]),
  ];

  static const List<RechargePack> rechargePacks = [
    RechargePack(100, 0.99, false),
    RechargePack(500, 3.99, true),
    RechargePack(1200, 7.99, false),
    RechargePack(3000, 14.99, false),
  ];

  static const Map<String, int> plusDiscountCodes = {
    'ANISPHERE': 20,
    'WEEBGOD': 30,
    'WELCOME14': 14,
    'ANIMASTER': 25,
  };

  static const List<String> plusFeatures = [
    'Unlimited True Fan attempts',
    'AI rating predictor',
    'AI review writer',
    'AI episode summaries',
    'AniDub — dub any clip',
    'Spoiler Shield AI',
    'Unlimited AniScan',
    'Custom app icons',
    'Profile themes & fonts',
    'Pin up to 5 posts',
    'Animated profile aura',
    'Exclusive store frames',
    'Early seasonal access',
    'Ad-free experience',
    '2× AniGold on tasks',
    'Priority in AniMatch',
    'Press Pass eligibility',
    'Translate any post free',
    'Exclusive Plus badge 💎',
    'Monthly Legendary pack',
  ];

  // ─────────────────────────────────────────── CARDS
  static const List<CardModel> cards = [
    CardModel(id: 'cd1', character: 'Frieren', anime: 'Frieren', rarity: CardRarity.legendary, emoji: '🧝‍♀️', power: 9800, owned: true, imagePath: 'assets/images/cards/frieren.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b176754-PCnpqIOkjhFk.png'),
    CardModel(id: 'cd2', character: 'Gojo Satoru', anime: 'Jujutsu Kaisen', rarity: CardRarity.legendary, emoji: '🔮', power: 9900, owned: true, imagePath: 'assets/images/cards/gojo.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b127691-9zqh1xpIubn7.png'),
    CardModel(id: 'cd3', character: 'Levi', anime: 'Attack on Titan', rarity: CardRarity.epic, emoji: '⚔️', power: 8700, owned: true, imagePath: 'assets/images/cards/levi.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b45627-CR68RyZmddGG.png'),
    CardModel(id: 'cd4', character: 'Denji', anime: 'Chainsaw Man', rarity: CardRarity.epic, emoji: '🪚', power: 8200, owned: true, imagePath: 'assets/images/cards/denji.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b130102-FO1VHNnEnLlB.png'),
    CardModel(id: 'cd5', character: 'Thorfinn', anime: 'Vinland Saga', rarity: CardRarity.rare, emoji: '🪓', power: 7100, owned: true, imagePath: 'assets/images/cards/thorfinn.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b10138-zOPrka0ddZOR.png'),
    CardModel(id: 'cd6', character: 'Anya', anime: 'Spy x Family', rarity: CardRarity.rare, emoji: '🥜', power: 6600, owned: true, imagePath: 'assets/images/cards/anya.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b138100-4Li0tWRCa5bQ.png'),
    CardModel(id: 'cd7', character: 'Tanjiro', anime: 'Demon Slayer', rarity: CardRarity.epic, emoji: '🗡️', power: 8400, owned: false, imagePath: 'assets/images/cards/tanjiro.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b126071-BTNEc1nRIv68.png'),
    CardModel(id: 'cd8', character: 'Sung Jinwoo', anime: 'Solo Leveling', rarity: CardRarity.legendary, emoji: '⚡', power: 9600, owned: false, imagePath: 'assets/images/cards/sung_jinwoo.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b129928-BCEjVaP0AQSw.png'),
    CardModel(id: 'cd9', character: 'Killua', anime: 'Hunter x Hunter', rarity: CardRarity.epic, emoji: '⚡', power: 8500, owned: false, imagePath: 'assets/images/cards/killua.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b27-Z5O02kQUydpT.jpg'),
    CardModel(id: 'cd10', character: 'Naruto', anime: 'Naruto', rarity: CardRarity.rare, emoji: '🍥', power: 7400, owned: false, imagePath: 'assets/images/cards/naruto.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b17-phjcWCkRuIhu.png'),
    CardModel(id: 'cd11', character: 'Power', anime: 'Chainsaw Man', rarity: CardRarity.common, emoji: '🩸', power: 5200, owned: false, imagePath: 'assets/images/cards/power.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b137079-6yLEUYR3bmpr.png'),
    CardModel(id: 'cd12', character: 'Zenitsu', anime: 'Demon Slayer', rarity: CardRarity.common, emoji: '⚡', power: 5400, owned: false, imagePath: 'assets/images/cards/zenitsu.png', imageUrl: 'https://s4.anilist.co/file/anilistcdn/character/large/b129131-FZrQ7lSlxmEr.png'),
  ];

  // ─────────────────────────────────────────── TRUE FAN QUIZ
  static List<QuizQuestion> trueFanQuestions(String anime) => [
        const QuizQuestion('🧝‍♀️', 'Frieren', ['Frieren', 'Fern', 'Eisen']),
        const QuizQuestion('🧙', 'Himmel the Hero', ['Stark', 'Himmel the Hero', 'Heiter']),
        const QuizQuestion('🛡️', 'Stark', ['Stark', 'Sein', 'Eisen']),
        const QuizQuestion('📿', 'Fern', ['Fern', 'Frieren', 'Übel']),
        const QuizQuestion('🍷', 'Heiter', ['Sein', 'Heiter', 'Stark']),
        const QuizQuestion('⚔️', 'Eisen', ['Eisen', 'Himmel the Hero', 'Stark']),
        const QuizQuestion('🔮', 'Serie', ['Flamme', 'Serie', 'Frieren']),
        const QuizQuestion('🌸', 'Übel', ['Übel', 'Fern', 'Frieren']),
        const QuizQuestion('📖', 'Flamme', ['Flamme', 'Serie', 'Heiter']),
        const QuizQuestion('🗡️', 'Wirbel', ['Wirbel', 'Stark', 'Sein']),
      ];

  // ─────────────────────────────────────────── LEAGUE
  static List<LeaderEntry> get leagueLeaders => [
        const LeaderEntry(1, sakura, 2840),
        const LeaderEntry(2, kenji, 2710),
        const LeaderEntry(3, aoi, 2390),
        const LeaderEntry(4, mei, 2110),
        const LeaderEntry(5, mainUser, 1980),
        const LeaderEntry(6, ryuu, 1740),
      ];

  static DateTime _ago(Duration d) => DateTime.now().subtract(d);
}

// ───────────────────────────── lightweight data records
class AniMatch {
  final UserModel user;
  final int percent;
  final List<String> shared;
  const AniMatch(this.user, this.percent, this.shared);
}

class NewsItem {
  final String title;
  final String source;
  final String category;
  final DateTime time;
  const NewsItem(this.title, this.source, this.category, this.time);
}

class ChartEntry {
  final int rank;
  final String title;
  final double score;
  final int ratings;
  final int movement; // +up / -down / 0
  const ChartEntry(this.rank, this.title, this.score, this.ratings, this.movement);
}

enum NotifType { follow, like, newEpisode, streakWarning, streakBonus, friend, smart, trueFan }

class NotificationItem {
  final NotifType type;
  final UserModel? user;
  final String text;
  final DateTime time;
  final String? anime;
  const NotificationItem(this.type, this.user, this.text, this.time, {this.anime});
}

class Achievement {
  final String name;
  final String emoji;
  final String desc;
  final String category;
  final bool unlocked;
  final double progress;
  final String progressLabel;
  const Achievement(this.name, this.emoji, this.desc, this.category, this.unlocked, this.progress, this.progressLabel);
}

class StoreItem {
  final String name;
  final String sub;
  final int price;
  final String emoji;
  final List<Color> gradient;
  const StoreItem(this.name, this.sub, this.price, this.emoji, this.gradient);
}

class RechargePack {
  final int gems;
  final double price;
  final bool bestValue;
  const RechargePack(this.gems, this.price, this.bestValue);
}

class QuizQuestion {
  final String emoji;
  final String answer;
  final List<String> options;
  const QuizQuestion(this.emoji, this.answer, this.options);
}

class LeaderEntry {
  final int rank;
  final UserModel user;
  final int lp;
  const LeaderEntry(this.rank, this.user, this.lp);
}
