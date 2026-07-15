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

  /// Ensure a signed-in user, creating a guest session if there is none.
  /// Memoized so concurrent callers share one sign-in attempt; a failure
  /// clears the memo so the next call retries.
  Future<User> initAuth() {
    final existing = _auth.currentUser;
    if (existing != null) return Future.value(existing);
    return _pending ??= () async {
      try {
        final user = (await _auth.signInAnonymously()).user;
        if (user == null) throw StateError('No Firebase user after sign-in');
        debugPrint('[AuthService] guest session: ${user.uid}');
        return user;
      } on FirebaseAuthException catch (e) {
        debugPrint('[AuthService] anonymous sign-in failed: [${e.code}] ${e.message}');
        _pending = null;
        rethrow;
      } catch (e) {
        debugPrint('[AuthService] anonymous sign-in failed: $e');
        _pending = null;
        rethrow;
      }
    }();
  }

  /// Explicit guest sign-in (the "Continue as Guest" button).
  Future<User> signInAnonymously() => initAuth();

  Future<void> signOut() async {
    _pending = null;
    await _auth.signOut();
  }
}
