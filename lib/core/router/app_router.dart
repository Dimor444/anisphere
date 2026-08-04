import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/news.dart';
import '../../data/models/post.dart';
import '../../features/achievements/achievements_screen.dart';
import '../../features/ani_videos/ani_videos_screen.dart';
import '../../features/ani_videos/upload_video_screen.dart';
import '../../features/anime_detail/anime_detail_screen.dart';
import '../../features/aniscan/aniscan_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/auth/signin_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/challenges/challenges_screen.dart';
import '../../features/community/club_detail_screen.dart';
import '../../features/community/community_screen.dart';
import '../../features/community/room_detail_screen.dart';
import '../../features/community_vote/community_vote_history_screen.dart';
import '../../features/community_vote/community_vote_screen.dart';
import '../../features/discover/discover_screen.dart';
import '../../features/feed/create_post_screen.dart';
import '../../features/feed/feed_screen.dart';
import '../../features/feed/hashtag_feed_screen.dart';
import '../../features/feed/post_detail_screen.dart';
import '../../features/stories/story_providers.dart';
import '../../features/stories/story_viewer_screen.dart';
import '../../features/fm_radio/fm_radio_screen.dart';
import '../../features/messages/chat_screen.dart';
import '../../features/messages/messages_screen.dart';
import '../../features/my_list/my_list_detail_screen.dart';
import '../../features/my_list/my_list_screen.dart';
import '../../features/news/news_detail_screen.dart';
import '../../features/news/news_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/observatory/observatory_screen.dart';
import '../../features/profile/card_collection_screen.dart';
import '../../features/profile/followers_screen.dart';
import '../../features/profile/following_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/time_capsule_screen.dart';
import '../../features/profile/wrapped_screen.dart';
import '../../features/seasonal/seasonal_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/trending/trending_detail_screen.dart';
import '../../features/trending/trending_screen.dart';
import '../../features/wallet/wallet_screen.dart';
import '../../services/trending_service.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Slide-up transition used for full-screen pushed routes.
CustomTransitionPage<void> _fade(Widget child, GoRouterState state) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

GoRoute _top(String path, Widget Function(BuildContext, GoRouterState) builder) =>
    GoRoute(path: path, parentNavigatorKey: _rootKey, pageBuilder: (c, s) => _fade(builder(c, s), s));

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/signin', builder: (_, __) => const SignInScreen()),
    GoRoute(path: '/signup', builder: (_, __) => const SignUpScreen()),

    // Main tabbed shell.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/feed', builder: (_, __) => const FeedScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/ani-videos', builder: (_, __) => const AniVideosScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen())]),
      ],
    ),

    // Former tabs, now pushed full-screen from the drawer (screens unchanged).
    _top('/trending', (c, s) => const TrendingScreen()),
    _top('/my-list', (c, s) => const MyListScreen()),
    _top('/community', (c, s) => const CommunityScreen()),
    _top('/room/:id', (c, s) => RoomDetailScreen(roomId: s.pathParameters['id']!)),

    // Full-screen pushed routes (over the bottom nav).
    _top('/anime/:id', (c, s) => AnimeDetailScreen(animeId: s.pathParameters['id']!)),
    _top('/trending/anime/:id', (c, s) => TrendingDetailScreen(
          anilistId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
          anime: s.extra is TrendingAnime ? s.extra as TrendingAnime : null,
        )),
    _top('/messages', (c, s) => const MessagesScreen()),
    _top('/chat/:cid', (c, s) => ChatScreen(cid: s.pathParameters['cid']!)),
    _top('/notifications', (c, s) => const NotificationsScreen()),
    _top('/wallet', (c, s) => WalletScreen(initialTab: s.uri.queryParameters['tab'])),
    _top('/settings', (c, s) => const SettingsScreen()),
    _top('/challenges', (c, s) => const ChallengesScreen()),
    _top('/seasonal', (c, s) => const SeasonalScreen()),
    _top('/achievements', (c, s) => const AchievementsScreen()),
    _top('/ani-videos/upload', (c, s) => const UploadVideoScreen()),
    _top('/my-list/:id', (c, s) => MyListDetailScreen(anilistId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0)),
    _top('/observatory', (c, s) => const ObservatoryScreen()),
    _top('/fm-radio', (c, s) => const FmRadioScreen()),
    _top('/cards', (c, s) => const CardCollectionScreen()),
    _top('/aniscan', (c, s) => const AniScanScreen()),
    _top('/wrapped', (c, s) => const WrappedScreen()),
    _top('/time-capsule', (c, s) => const TimeCapsuleScreen()),
    _top('/create-post', (c, s) => const CreatePostScreen()),
    // '/feed/hashtag/…' must precede '/feed/:postId' so 'hashtag' never binds
    // as a post id.
    _top('/feed/hashtag/:tag', (c, s) => HashtagFeedScreen(tag: s.pathParameters['tag']!)),
    _top('/feed/:postId', (c, s) => PostDetailScreen(
          postId: s.pathParameters['postId']!,
          initial: s.extra is PostData ? s.extra as PostData : null,
        )),
    _top('/story', (c, s) => s.extra is StoryGroup
        ? StoryViewerScreen(group: s.extra as StoryGroup)
        : const StoryViewerFallback()),
    _top('/community-vote/history', (c, s) => const CommunityVoteHistoryScreen()),
    _top('/community-vote', (c, s) => const CommunityVoteScreen()),
    _top('/news', (c, s) => const NewsScreen()),
    _top('/news/:newsId', (c, s) => NewsDetailScreen(
          newsId: s.pathParameters['newsId']!,
          initial: s.extra is NewsArticle ? s.extra as NewsArticle : null,
        )),
    _top('/profile/:userId/followers', (c, s) => FollowersScreen(userId: s.pathParameters['userId']!)),
    _top('/profile/:userId/following', (c, s) => FollowingScreen(userId: s.pathParameters['userId']!)),
    _top('/profile/:userId', (c, s) => ProfileScreen(userId: s.pathParameters['userId']!)),
    _top('/club/:name', (c, s) => ClubDetailScreen(clubName: s.pathParameters['name']!)),
  ],
);
