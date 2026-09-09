import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/follow_service.dart';
import '../shared/providers/identity_provider.dart';

/// Reacts to the signed-in identity changing: tears down what belonged to the
/// old user, attaches what the new one needs.
///
/// WHY THIS IS NOT WIRED INTO [AuthService.signOut]
///
/// Two reasons, one structural and one behavioural.
///
/// Structural: every service imports [AuthService]. Having it import them back
/// to call their resets would be a cycle and would make the auth singleton
/// impossible to test alone. This module sits above both — it imports auth AND
/// the services, and is imported by neither, so the dependency arrows keep
/// pointing one way. `main()` installs it; nothing else references it.
///
/// Behavioural, and the decisive one: sign-out is not a function call, it is a
/// STATE TRANSITION, and it has more than one origin. A deliberate
/// [AuthService.signOut] is one. `_recoverFromDeadCredential` is another — it
/// signs out on a path that never touches signOut(). Teardown hung off the
/// button would miss that one silently. Both funnel through `_auth.signOut()`,
/// which emits on [AuthService.authStateChanges], so binding to the stream
/// catches every origin including ones not yet written.
class SessionLifecycle {
  SessionLifecycle._();
  static final SessionLifecycle instance = SessionLifecycle._();

  StreamSubscription<User?>? _sub;

  /// The uid this class has already ACTED on — not merely the last one seen.
  /// Every decision is a comparison against it, which is what makes repeated
  /// emissions of the same state free.
  String? _actedOn;

  /// Serializes the async reactions. A `listen` callback returning a Future is
  /// not awaited by the stream, so without this a sign-out immediately
  /// followed by a sign-in could interleave and let the teardown land after
  /// the attach — cancelling the subscription the attach had just made.
  Future<void> _queue = Future<void>.value();

  bool _installed = false;

  /// Subscribe to identity changes. Idempotent; extra calls are ignored.
  void install() {
    if (_installed) return;
    _installed = true;
    _sub = AuthService.instance.authStateChanges.listen(
      _onAuthState,
      onError: (Object e) => debugPrint('[SessionLifecycle] auth stream error: $e'),
    );
  }

  /// FirebaseAuth re-emits freely — the current value on subscribe, and again
  /// on token refreshes that leave the uid alone. Only a CHANGE of uid is a
  /// transition, so everything else returns here without touching a service.
  ///
  /// The guard and the bookkeeping are synchronous, before any await, so two
  /// emissions arriving back to back cannot both read a stale [_actedOn].
  void _onAuthState(User? user) {
    final next = user?.uid;
    final prev = _actedOn;
    if (next == prev) return;
    _actedOn = next;

    _queue = _queue
        .then((_) => _apply(prev: prev, next: next))
        .catchError((Object e) =>
            debugPrint('[SessionLifecycle] transition $prev -> $next failed: $e'));
  }

  /// The three transitions, and why a uid swap is both of the other two.
  ///
  /// A -> null is a teardown. null -> B is an attach. A -> B is a teardown
  /// THEN an attach, in that order and never overlapped: B's watch must not be
  /// started before A's is cancelled, or the cancel would take the new one
  /// down with it. Nothing produces A -> B today (only guests exist, and they
  /// pass through null), but real sign-in will, and the ordering is free now
  /// and easy to get wrong later.
  Future<void> _apply({required String? prev, required String? next}) async {
    if (prev != null) {
      debugPrint('[SessionLifecycle] identity left ($prev) — tearing down');
      await FollowService.instance.resetForSignOut();
      clearIdentityCache();
    }
    if (next != null) {
      debugPrint('[SessionLifecycle] identity arrived ($next) — attaching');
      await FollowService.instance.ensureFollowingWatch();
    }
  }

  /// Test seam: drop the subscription and the remembered uid so a test can
  /// install a fresh lifecycle against a new fake.
  @visibleForTesting
  Future<void> debugDispose() async {
    await _sub?.cancel();
    _sub = null;
    _actedOn = null;
    _installed = false;
    _queue = Future<void>.value();
  }
}
