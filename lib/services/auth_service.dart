import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

/// Why [AuthService.deleteAccount] did not end the session. Each value is a
/// different promise to the user, so the screen maps each to its own message.
enum AccountDeletionFailure {
  /// The server could not be reached before anything was sent. Nothing was
  /// changed.
  unreachable,

  /// The server rejected the request before its commit point. Nothing was
  /// changed.
  refused,

  /// The request may have reached the commit point — a timeout, a dropped
  /// connection, a server fault mid-request — and the account still works,
  /// so there is no telling. Retrying is safe: a repeat call on a deletion
  /// that was already accepted answers "accepted" without redoing anything.
  unconfirmed,
}

class AccountDeletionException implements Exception {
  const AccountDeletionException(this.failure, this.detail);
  final AccountDeletionFailure failure;
  final String detail;
  @override
  String toString() => 'AccountDeletionException(${failure.name}): $detail';
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
    // A cache wipe from a deletion may still be running. The wipe cannot
    // survive a session starting underneath it — see [clearLocalData].
    final clearing = _clearingLocalData;
    if (clearing != null) await clearing;
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
  ///
  /// `aniscan_used` is also NOT listed, but for the opposite reason, and it
  /// is the one exclusion that looks like a bug. It IS per-account — the
  /// lifetime AniScan count — so a sweep for user-scoped keys will find it
  /// and want to add it here. Do not. It gates the three free scans, and
  /// wiping it on sign-out makes that paywall farmable: sign out, sign back
  /// in, three more scans, repeat forever. The accepted cost is the other
  /// way round — a shared handset carries the previous person's count.
  /// Defined on AniScanController, which repeats this note.
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
    await _endSession();
  }

  /// The half of [signOut] after the flag, shared with [deleteAccount].
  Future<void> _endSession() async {
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

  static const String _functionsRegion = 'europe-west1';

  /// Long enough for a cold start plus the callable's own steps, short enough
  /// that a hung request becomes an answer while the user is still looking.
  static const Duration _deletionTimeout = Duration(seconds: 30);

  /// Callable codes that are answered before the handler reaches its commit
  /// point: the platform's own rejections (no function, no quota, App Check,
  /// no token) and the handler's argument checks. Everything else could have
  /// come from after it, and is [AccountDeletionFailure.unconfirmed].
  ///
  /// `internal` is deliberately NOT here although the handler's own "could
  /// not start" failure uses it — an uncaught fault after the commit point
  /// arrives as `internal` too, and the two are indistinguishable on the wire.
  static const Set<String> _refusedBeforeCommit = {
    'unauthenticated',
    'invalid-argument',
    'permission-denied',
    'failed-precondition',
    'not-found',
    'unimplemented',
    'resource-exhausted',
  };

  /// Deletes the signed-in account, then ends the session.
  ///
  /// ORDER: connectivity check, flag, call, then [_endSession].
  ///
  /// The check is a forced token refresh. It proves the server is reachable
  /// before anything is sent — the only point at which "nothing was changed"
  /// is certain rather than likely — and it hands the call a token with a
  /// full hour on it, so the call cannot fail on a refresh halfway through.
  ///
  /// The flag goes BEFORE the call for the reason it goes first in
  /// [signOut]: once the server has disabled the account, nothing on this
  /// device may mint a replacement guest. A process killed mid-call leaves it
  /// set, so the next launch opens on onboarding instead of silently swapping
  /// identities. If the server never got that far, Continue as Guest signs
  /// the SAME guest back in — signInAnonymously returns the current anonymous
  /// user when there is one.
  ///
  /// A failed call is not proof the account survived: the response can be
  /// lost after the server committed. So every failure re-checks the
  /// credential first. Dead means the server got as far as disabling it, and
  /// that is success. Alive means the flag is cleared and the failure thrown.
  ///
  /// Does NOT clear the offline cache — see [clearLocalData] for why that
  /// waits until the signed-in screens are gone.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AccountDeletionException(
          AccountDeletionFailure.refused, 'no session');
    }

    final preflight = await _credentialState(user);
    if (preflight == _Credential.unreachable) {
      throw const AccountDeletionException(
          AccountDeletionFailure.unreachable, 'token refresh failed');
    }
    if (preflight == _Credential.dead) {
      // Already disabled: an earlier attempt committed and its answer never
      // arrived. Nothing is left to call; finish the sign-out.
      debugPrint('[AuthService] deleteAccount: credential already dead — '
          'ending the session');
      _pending = null;
      await _setSignedOut(true);
      await _endSession();
      return;
    }

    _pending = null;
    await _setSignedOut(true);
    try {
      await FirebaseFunctions.instanceFor(region: _functionsRegion)
          .httpsCallable('deleteAccount',
              options: HttpsCallableOptions(timeout: _deletionTimeout))
          .call<Map<String, dynamic>>({'confirm': 'DELETE'});
    } catch (e) {
      if (await _credentialState(user) == _Credential.dead) {
        debugPrint('[AuthService] deleteAccount: call failed ($e) but the '
            'account is disabled — the server committed; ending the session');
      } else {
        await _setSignedOut(false);
        final code = e is FirebaseFunctionsException ? e.code : 'unknown';
        debugPrint('[AuthService] deleteAccount failed: [$code] $e');
        throw AccountDeletionException(
          _refusedBeforeCommit.contains(code)
              ? AccountDeletionFailure.refused
              : AccountDeletionFailure.unconfirmed,
          '[$code] $e',
        );
      }
    }
    await _endSession();
  }

  /// A forced refresh, read three ways. Only [deadCredentialCodes] count as
  /// dead — the same allowlist [initAuth] trusts — and every other failure
  /// is "could not tell", never "gone".
  Future<_Credential> _credentialState(User user) async {
    try {
      await user.getIdToken(true).timeout(validationTimeout);
      return _Credential.alive;
    } on FirebaseAuthException catch (e) {
      if (deadCredentialCodes.contains(e.code)) return _Credential.dead;
      debugPrint('[AuthService] credential check: [${e.code}] ${e.message}');
      return _Credential.unreachable;
    } catch (e) {
      debugPrint('[AuthService] credential check: $e');
      return _Credential.unreachable;
    }
  }

  Future<void>? _clearingLocalData;

  /// Terminates Firestore and wipes its on-disk cache, so a deleted account's
  /// documents and unsent writes do not stay on the handset.
  ///
  /// Call it AFTER the signed-in screens are gone. `clearPersistence` only
  /// works on an instance that is terminated or not started, and terminating
  /// drops the native instance — so any Firestore call that lands between the
  /// two steps starts a fresh instance and the wipe is refused. A screen still
  /// mounted is the likeliest source of that call. One refusal is retried
  /// after a second terminate; a second is logged and the cache stays.
  ///
  /// No restart is needed afterwards: the next Firestore call builds a new
  /// native instance from the settings the Dart side still holds, emulator
  /// host included. [signInAsGuest] waits for this to finish.
  Future<void> clearLocalData() =>
      _clearingLocalData ??= _clearLocalData().whenComplete(() {
        _clearingLocalData = null;
      });

  Future<void> _clearLocalData() async {
    final firestore = FirebaseFirestore.instance;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await firestore.terminate();
        await firestore.clearPersistence();
        debugPrint('[AuthService] offline cache cleared');
        return;
      } catch (e) {
        debugPrint('[AuthService] offline cache wipe, attempt $attempt: $e');
      }
    }
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

enum _Credential { alive, dead, unreachable }
