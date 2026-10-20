// Auth session-recovery tests, against the Firebase AUTH EMULATOR.
//
// A cached session is restored from the keychain without any server contact,
// so the app validates it at startup. Only a DEFINITIVE answer may end it —
// the four codes the SDK raises solely from the server saying so. Anything
// else keeps the session and tells the player, who alone decides to give the
// account up: for a guest, signing out is permanent.
//
// The emulator answers definitively for a DISABLED account (USER_DISABLED →
// user-disabled). For a DELETED account it answers INVALID_REFRESH_TOKEN,
// which the SDK reports as its catch-all `internal-error` — the answer that
// used to sign players out, and the ambiguous case here. Production documents
// USER_NOT_FOUND for a deleted account.
//
// AuthService.debugTokenFetcher forces the token REFRESH where a test needs
// it. That is not a faked error: the refresh runs for real against the
// emulator and the FirebaseAuthException comes from the SDK. The seam only
// skips the hour-long wait for the cached token to expire on its own.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';

const _project = 'anisphere-36cb0';
const _authEmu = 'http://127.0.0.1:9099';
const _owner = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

/// Disables [uid] server-side, as an admin would. The client keeps its session.
Future<void> disableServerSide(String uid) async {
  final res = await http.post(
    Uri.parse('$_authEmu/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:update'),
    headers: _owner,
    body: jsonEncode({'localId': uid, 'disableUser': true}),
  );
  expect(res.statusCode, 200, reason: 'emulator disable failed: ${res.body}');
}

/// Deletes [uid] server-side. The client keeps its session.
Future<void> deleteServerSide(String uid) async {
  final res = await http.post(
    Uri.parse('$_authEmu/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:delete'),
    headers: _owner,
    body: jsonEncode({'localId': uid}),
  );
  expect(res.statusCode, 200, reason: 'emulator delete failed: ${res.body}');
}

Future<int> accountCount() async {
  final res = await http.get(
    Uri.parse('$_authEmu/emulator/v1/projects/$_project/accounts'),
    headers: _owner,
  );
  final users = (jsonDecode(res.body) as Map<String, dynamic>)['userInfo'] as List<dynamic>?;
  return users?.length ?? 0;
}

/// A guest with a cached session, as after a cold start: signed in, then the
/// memo dropped so the next [AuthService.initAuth] validates it.
Future<String> cachedGuest() async {
  await AuthService.instance.signOut();
  final uid = (await AuthService.instance.signInAsGuest()).uid;
  AuthService.instance.debugResetMemo();
  return uid;
}

/// The refresh, forced, recording what the SDK threw.
FirebaseAuthException? observed;
Future<String?> forcedRefresh(User u) async {
  try {
    return await u.getIdToken(true);
  } on FirebaseAuthException catch (e) {
    observed = e;
    rethrow;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
  });

  setUp(() => observed = null);
  tearDown(() => AuthService.debugTokenFetcher = null);

  testWidgets('DEAD credential: a disabled account recovers to a working session', (tester) async {
    final firstUid = await cachedGuest();
    await disableServerSide(firstUid);
    expect(FirebaseAuth.instance.currentUser?.uid, firstUid,
        reason: 'the client still believes it is signed in');

    AuthService.debugTokenFetcher = forcedRefresh;
    final recovered = await AuthService.instance.initAuth();
    expect(observed?.code, 'user-disabled', reason: 'the SDK\'s definitive code for a disabled account');
    expect(AuthService.deadCredentialCodes, contains(observed!.code));

    expect(recovered.uid, isNot(firstUid), reason: 'must be a NEW session');
    expect(recovered.isAnonymous, isTrue);
    expect(AuthService.instance.sessionUnconfirmed.value, isFalse);

    // The recovered session must actually work, not merely exist: a server
    // read of a collection the rules gate on signedIn().
    AuthService.debugTokenFetcher = null;
    final probe = await FirebaseFirestore.instance
        .collection('users')
        .limit(1)
        .get(const GetOptions(source: Source.server));
    expect(probe.metadata.isFromCache, isFalse,
        reason: 'recovered session must reach the server, not fall back to cache');
  });

  testWidgets('AMBIGUOUS answer: internal-error keeps the session and tells the player', (tester) async {
    final uid = await cachedGuest();
    await deleteServerSide(uid);
    final accountsBefore = await accountCount();

    AuthService.debugTokenFetcher = forcedRefresh;
    final kept = await AuthService.instance.initAuth();
    expect(observed?.code, 'internal-error',
        reason: 'the emulator\'s INVALID_REFRESH_TOKEN reaches Dart as the catch-all');
    expect(kept.uid, uid, reason: 'an ambiguous answer must NOT replace the session');
    expect(FirebaseAuth.instance.currentUser?.uid, uid);
    expect(await accountCount(), accountsBefore, reason: 'no guest may be minted behind the player\'s back');
    expect(AuthService.instance.sessionUnconfirmed.value, isTrue,
        reason: 'the player must be told, so starting over is their choice');

    // Retry: still no definitive answer — nothing changes.
    expect(await AuthService.instance.recheckSession(), isFalse);
    expect(FirebaseAuth.instance.currentUser?.uid, uid);
    expect(AuthService.instance.sessionUnconfirmed.value, isTrue);
  });

  testWidgets('AMBIGUOUS answer, then the server confirms: Retry clears it', (tester) async {
    final uid = await cachedGuest();
    AuthService.debugTokenFetcher =
        (u) => Future<String?>.error(FirebaseAuthException(code: 'internal-error'));
    await AuthService.instance.initAuth();
    expect(AuthService.instance.sessionUnconfirmed.value, isTrue);

    AuthService.debugTokenFetcher = null; // the server answers again
    expect(await AuthService.instance.recheckSession(), isTrue);
    expect(AuthService.instance.sessionUnconfirmed.value, isFalse);
    expect(FirebaseAuth.instance.currentUser?.uid, uid);
  });

  testWidgets('NOT DEFINITIVE: no other failure signs the user out', (tester) async {
    // Codes the server may answer without settling anything, a code a future
    // SDK may add, and the offline case. Only an answer from the server raises
    // the banner; being offline is what every screen already shows.
    const flagged = {'internal-error': true, 'too-many-requests': true, 'some-future-sdk-code': true,
        'network-request-failed': false};
    for (final entry in flagged.entries) {
      final cachedUid = await cachedGuest();
      AuthService.debugTokenFetcher =
          (u) => Future<String?>.error(FirebaseAuthException(code: entry.key));
      final kept = await AuthService.instance.initAuth();
      expect(kept.uid, cachedUid, reason: '[${entry.key}] must keep the SAME session');
      expect(FirebaseAuth.instance.currentUser, isNotNull, reason: '[${entry.key}] must not sign the user out');
      expect(AuthService.instance.sessionUnconfirmed.value, entry.value,
          reason: '[${entry.key}] unconfirmed flag');
    }

    // A timeout is offline too.
    final beforeUid = await cachedGuest();
    AuthService.debugTokenFetcher =
        (u) => Future<String?>.delayed(const Duration(seconds: 30), () => 'never');
    final keptAfterTimeout = await AuthService.instance.initAuth();
    expect(keptAfterTimeout.uid, beforeUid, reason: 'timeout must keep the session');
    expect(AuthService.instance.sessionUnconfirmed.value, isFalse);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('FAST PATH: a valid cached token does no network round trip', (tester) async {
    await cachedGuest();
    var fetches = 0;
    AuthService.debugTokenFetcher = (u) {
      fetches++;
      return u.getIdToken(); // non-forced: cache hit, no network
    };
    final sw = Stopwatch()..start();
    await AuthService.instance.initAuth();
    sw.stop();

    expect(fetches, 1, reason: 'validation runs exactly once per launch');
    expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'valid cached token must not wait on the network');
  });
}
