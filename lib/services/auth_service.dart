import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  /// Memoized, so validation costs one round trip per app launch at most and
  /// concurrent callers share it; a failure clears the memo so the next call
  /// retries.
  Future<User> initAuth() {
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

  /// Explicit guest sign-in (the "Continue as Guest" button).
  Future<User> signInAnonymously() => initAuth();

  Future<void> signOut() async {
    _pending = null;
    await _auth.signOut();
  }
}
