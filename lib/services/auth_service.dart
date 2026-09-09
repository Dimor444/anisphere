import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown by [AuthService.initAuth] when the user DELIBERATELY signed out and
/// has not chosen an identity since.
///
/// Deliberately not a [FirebaseAuthException]: this is not a Firebase failure,
/// and borrowing that code space would let it match
/// [AuthService.deadCredentialCodes] and be mistaken for a dead credential —
/// which recovers by minting a guest, the exact behaviour this prevents.
class SignedOutException implements Exception {
  const SignedOutException();
  @override
  String toString() =>
      'SignedOutException: signed out deliberately; no identity until the '
      'user picks one (sign in, or Continue as Guest).';
}

/// App identity. The email/password UI is not wired to FirebaseAuth yet, so a
/// guest (anonymous) session is the working identity path — [initAuth] is the
/// single entry point every Firebase-backed feature goes through, and when
/// real providers land only this service needs to change.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  /// Fires on sign-in/sign-out — drive reactive UI off this.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User>? _pending;

  /// Set by [signOut], cleared only by [signInAsGuest] (and, when real
  /// providers land, by a real sign-in). While it is true [initAuth] refuses
  /// instead of minting.
  ///
  /// `null` means "not read from disk yet" — distinct from `false`, so
  /// [_isSignedOut] knows whether it still owes a read.
  bool? _signedOut;

  static const String _signedOutKey = 'auth_deliberate_signout_v1';

  /// Reads the flag, hydrating from disk at most once.
  ///
  /// Fails CLOSED on a read error: a device that cannot answer is treated as
  /// signed out, because the recovery is one tap on Continue as Guest whereas
  /// the opposite mistake silently mints the guest this whole mechanism
  /// exists to prevent.
  Future<bool> _isSignedOut() async {
    final cached = _signedOut;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      return _signedOut = prefs.getBool(_signedOutKey) ?? false;
    } catch (e) {
      debugPrint('[AuthService] signed-out flag read failed ($e) — '
          'treating as signed out');
      return _signedOut = true;
    }
  }

  /// Hydrate the flag before the first [initAuth]. Called from `main()`.
  ///
  /// Only an optimisation: [initAuth] hydrates lazily anyway, so skipping this
  /// costs a disk read on the first call but never changes the outcome. It
  /// exists so the check is already resolved by the time the tree builds.
  Future<void> hydrateSession() => _isSignedOut();

  /// Test seam: drop the hydrated flag so the next read comes off disk again.
  @visibleForTesting
  void debugResetSignedOutFlag() => _signedOut = null;

  /// Auth codes that mean the cached credential is DEAD: the account is gone,
  /// disabled, or its refresh token is permanently rejected. Nothing recovers
  /// these by waiting, so a guest session carrying one is discarded.
  ///
  /// `internal-error` is in here because that is what the iOS SDK reports when
  /// securetoken.googleapis.com answers a refresh with HTTP 400 — the exact
  /// signature of an account that was deleted out from under a live keychain
  /// session.
  ///
  /// This is an ALLOWLIST on purpose. Every other failure — most importantly
  /// `network-request-failed`, timeouts, and any code added by a future SDK —
  /// is treated as transient and the session is kept. Dropped wifi must never
  /// cost a user their account.
  static const Set<String> deadCredentialCodes = {
    'user-not-found',
    'user-disabled',
    'user-token-expired',
    'invalid-user-token',
    'internal-error',
  };

  /// Test seam. `FirebaseAuth.instance` is a hard singleton with no injection
  /// point, and the failure this guards against only becomes observable once a
  /// cached token has EXPIRED — which a test cannot wait an hour for. Tests
  /// substitute the token fetch to reach that moment; production always uses
  /// the non-forced [User.getIdToken] fast path below.
  @visibleForTesting
  static Future<String?> Function(User user)? debugTokenFetcher;

  /// Test seam: drop the memoized result WITHOUT touching the session, so a
  /// test can reproduce a cold start that restores a cached user from the
  /// keychain. [signOut] cannot stand in for this — it clears `currentUser`,
  /// which destroys the very state under test.
  @visibleForTesting
  void debugResetMemo() => _pending = null;

  /// Upper bound on how long a cold start may wait for token validation.
  /// Hitting it is treated as transient, so a slow network delays startup but
  /// never signs anyone out.
  static const Duration validationTimeout = Duration(seconds: 8);

  /// Ensure a signed-in user, creating a guest session if there is none.
  ///
  /// A cached user is VALIDATED before it is trusted. `_auth.currentUser` is
  /// restored from the keychain without ever contacting the server, so a
  /// session whose account no longer exists looks perfectly healthy here while
  /// every credentialed call it goes on to make fails. That state survives
  /// restarts, which is what made it a wedge rather than a blip.
  ///
  /// REFUSES with [SignedOutException] after a deliberate [signOut]. "No
  /// session yet" and "signed out" are indistinguishable in FirebaseAuth —
  /// `currentUser` is null for both — so the difference is carried by a flag
  /// rather than derived. Only [signInAsGuest] (and, later, a real sign-in)
  /// clears it, which is why no service can mint one by accident: they all
  /// come through here.
  ///
  /// The check runs FIRST and OUTSIDE the memo, so a refusal neither populates
  /// nor churns [_pending].
  ///
  /// Memoized, so validation costs one round trip per app launch at most and
  /// concurrent callers share it; a failure clears the memo so the next call
  /// retries.
  Future<User> initAuth() async {
    if (await _isSignedOut()) throw const SignedOutException();
    return _pending ??= () async {
      try {
        final existing = _auth.currentUser;
        if (existing != null) return await _validated(existing);
        return await _createGuestSession();
      } catch (e) {
        _pending = null;
        rethrow;
      }
    }();
  }

  /// Returns [existing] if its credential still works, otherwise recovers.
  ///
  /// FAST PATH: `getIdToken()` without `forceRefresh` returns the cached token
  /// with NO network round trip while it is still valid (~7ms), so a healthy
  /// cold start is not slowed down. It only reaches the network once the token
  /// has expired — which is exactly the moment a dead account is detectable.
  Future<User> _validated(User existing) async {
    try {
      final fetch = debugTokenFetcher?.call(existing) ?? existing.getIdToken();
      await fetch.timeout(validationTimeout);
      return existing;
    } on FirebaseAuthException catch (e) {
      if (!deadCredentialCodes.contains(e.code)) {
        // Transient: keep the session and let the caller's own retry handle it.
        debugPrint('[AuthService] token check failed transiently '
            '([${e.code}] ${e.message}) — keeping session ${existing.uid}');
        return existing;
      }
      return _recoverFromDeadCredential(existing, e.code);
    } on TimeoutException {
      debugPrint('[AuthService] token check timed out after '
          '${validationTimeout.inSeconds}s — keeping session ${existing.uid}');
      return existing;
    } catch (e) {
      // Unknown failure shape — treat as transient. Signing out on something
      // we do not understand is the one outcome we cannot take back.
      debugPrint('[AuthService] token check failed ($e) — keeping session ${existing.uid}');
      return existing;
    }
  }

  /// The credential is provably dead. A guest session is disposable, so it is
  /// replaced silently. A real account is NOT — its session is cleared so the
  /// UI can route to sign-in, but no guest session is minted in its place,
  /// because silently swapping someone's identity for a fresh anonymous one
  /// would hide the fact that they were signed out.
  Future<User> _recoverFromDeadCredential(User existing, String code) async {
    final wasAnonymous = existing.isAnonymous;
    debugPrint('[AuthService] cached credential is dead ([$code]) for '
        '${existing.uid} (anonymous: $wasAnonymous) — signing out');
    await _auth.signOut();

    if (!wasAnonymous) {
      throw FirebaseAuthException(
        code: code,
        message: 'Signed-in account is no longer valid; sign in again.',
      );
    }
    return _createGuestSession();
  }

  Future<User> _createGuestSession() async {
    try {
      final user = (await _auth.signInAnonymously()).user;
      if (user == null) throw StateError('No Firebase user after sign-in');
      debugPrint('[AuthService] guest session: ${user.uid}');
      return user;
    } on FirebaseAuthException catch (e) {
      debugPrint('[AuthService] anonymous sign-in failed: [${e.code}] ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AuthService] anonymous sign-in failed: $e');
      rethrow;
    }
  }

  /// The user CHOOSING guest — the "Continue as Guest" button, and the only
  /// sanctioned way a guest is minted.
  ///
  /// This is why it is not [initAuth]: that ensures an identity and must
  /// refuse after a deliberate sign-out, while this one IS the deliberate
  /// choice that lifts the refusal. Services only ever reach [initAuth], so
  /// none of them can mint by accident — which was the whole defect.
  ///
  /// Clears the flag first, then mints INTO the memo so a concurrent
  /// [initAuth] shares this session rather than racing a second one. A failed
  /// mint clears the memo, matching [initAuth] — the sign-in screen offers a
  /// retry, and a poisoned memo would make every retry fail forever.
  Future<User> signInAsGuest() async {
    await _setSignedOut(false);
    return _pending = () async {
      try {
        return await _createGuestSession();
      } catch (e) {
        _pending = null;
        rethrow;
      }
    }();
  }

  /// User-scoped SharedPreferences keys wiped on sign-out.
  ///
  /// These are per-ACCOUNT, not per-device: left behind, the next person to
  /// sign in on this handset inherits the previous user's search history,
  /// their remaining daily challenge attempts, and their unclaimed AniGold.
  ///
  /// Deliberately NOT listed: `app_language` is a device preference the user
  /// set for the handset, not for the account, and `trending_cache_*` is
  /// global anime data that belongs to nobody.
  static const List<String> _userScopedPrefKeys = [
    'search_history_v2',
    'search_history_v1', // legacy key, still read by SearchHistory
    'challenge_attempts_count',
    'challenge_attempts_date',
    'pending_anigold',
  ];

  /// Ends the session and clears the local state that belonged to it.
  ///
  /// ORDER MATTERS, and it is: flag, prefs wipe, then `_auth.signOut()`.
  ///
  /// The flag goes first because it is what stops the next [initAuth] from
  /// minting a replacement guest. Set it after the session is torn down and
  /// any service call landing in that window sees "no user, not signed out" —
  /// which is the mint path this exists to close.
  ///
  /// Both bookkeeping steps swallow their failures, for one shared reason: a
  /// step that throws must never leave the session alive, which is the outcome
  /// if `_auth.signOut()` sits behind it. The residual risk runs the other way
  /// — if `_auth.signOut()` itself throws, the keys are already gone while the
  /// session survives — and that is the correct side to fail on, since a
  /// signed-in user losing their own search history is a nuisance where a
  /// signed-out-looking user keeping a live session is a leak.
  Future<void> signOut() async {
    _pending = null;
    await _setSignedOut(true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _userScopedPrefKeys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('[AuthService] prefs wipe on sign-out failed (continuing): $e');
    }
    await _auth.signOut();
  }

  /// Sets the flag in memory and mirrors it to disk.
  ///
  /// The in-memory write happens FIRST and unconditionally, so the current
  /// process is correct even if the disk write throws. A failed write is
  /// swallowed for the same reason the prefs wipe is: bookkeeping that throws
  /// must never leave [signOut] short of `_auth.signOut()` with the session
  /// still alive.
  ///
  /// The residual risk is one-sided and worth naming: if the write fails while
  /// setting `true`, this process still refuses, but a force-quit loses the
  /// flag and the next launch mints a guest. That is the same outcome as
  /// before this change, so a failure degrades to the old behaviour rather
  /// than to a worse one.
  Future<void> _setSignedOut(bool value) async {
    _signedOut = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_signedOutKey, value);
    } catch (e) {
      debugPrint('[AuthService] signed-out flag write ($value) failed '
          '(continuing, in-memory value stands): $e');
    }
  }
}
