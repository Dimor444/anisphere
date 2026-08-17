import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/observatory_service.dart';

/// The two Firestore aggregations the Observatory renders.
///
/// Both are real counts. [totalMembers] is an unfiltered count() over `users`;
/// [postsToday] is a range count() over `posts.createdAt` since 00:00 UTC.
class ObservatoryStats {
  final int totalMembers;
  final int postsToday;

  const ObservatoryStats({required this.totalMembers, required this.postsToday});
}

/// Session-cached (Riverpod default). Retry / pull-to-refresh via
/// `ref.invalidate(observatoryStatsProvider)`.
final observatoryStatsProvider = FutureProvider<ObservatoryStats>((ref) async {
  final svc = ObservatoryService.instance;
  final results = await Future.wait([
    svc.fetchTotalMembers(),
    svc.fetchPostsToday(),
  ]);
  return ObservatoryStats(totalMembers: results[0], postsToday: results[1]);
});

/// Top anime by AniList's GLOBAL popularity figure. No geographic dimension
/// exists on this data — the UI labels it as worldwide.
final globalPopularProvider = FutureProvider<List<PopularAnime>>((ref) {
  return ObservatoryService.instance.fetchGlobalPopular();
});
