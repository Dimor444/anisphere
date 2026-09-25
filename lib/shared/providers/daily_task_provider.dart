import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/currency_service.dart';

// The daily-task providers. autoDispose and gated on a session like every
// other Firestore stream here, for the reason a keepAlive listener across a
// sign-out has already cost us once: config/, task_claims/ and likes are all
// read only by signed-in users, and a listener with no session is refused.
//
// Three providers, not one, for the same reason the catalogue has two: the
// config, today's likes and today's claim are separate reads that change at
// separate times. A new like should move the bar without re-reading the
// config, and a claim landing should not re-run the likes query.

/// config/daily_tasks by id, or null when there is nothing to show.
final dailyTasksProvider = StreamProvider.autoDispose<Map<String, DailyTask>?>((ref) {
  if (AuthService.instance.uid == null) return Stream.value(null);
  return CurrencyService.instance.watchDailyTasks();
});

/// Posts liked today, capped at the task's target — for DISPLAY. Keyed by the
/// target so the cap comes from the catalogue and not from a number here.
final reactionsTodayProvider = StreamProvider.autoDispose.family<int, int>((ref, target) {
  final uid = AuthService.instance.uid;
  if (uid == null) return Stream.value(0);
  return CurrencyService.instance.watchReactionsToday(uid, target);
});

/// Whether today's claim for a task id is already paid.
final taskClaimedProvider = StreamProvider.autoDispose.family<bool, String>((ref, taskId) {
  final uid = AuthService.instance.uid;
  if (uid == null) return Stream.value(false);
  return CurrencyService.instance.watchTaskClaimed(uid, taskId);
});
