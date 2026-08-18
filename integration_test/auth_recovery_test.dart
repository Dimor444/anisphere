// Auth session-recovery tests, against the Firebase AUTH EMULATOR.
//
// Reproduces the production failure that wedged the app: an anonymous account
// deleted server-side while the client still holds its session. The client
// keeps believing it is signed in (currentUser is restored from the keychain
// with no server contact), but every credentialed call fails, and the state
// survives restarts.
//
// The dead-credential test forces the token REFRESH path via
// AuthService.debugTokenFetcher. That is not a faked error: the refresh runs
// for real against the emulator with a genuinely deleted account, and the
// FirebaseAuthException comes from the SDK. The seam only skips the hour-long
// wait for the cached token to expire on its own, which is the moment
// production reaches naturally.
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
const _authEmu = 'http://localhost:9099';

/// Deletes every account in the auth emulator — the server-side half of the
/// failure. The client is untouched and keeps its cached session.
Future<void> deleteAllAccountsServerSide() async {
  final res = await http.delete(
    Uri.parse('$_authEmu/emulator/v1/projects/$_project/accounts'),
    headers: const {'Authorization': 'Bearer owner'},
  );
  expect(res.statusCode, anyOf(200, 204), reason: 'emulator account wipe failed: ${res.body}');
}

Future<int> accountCount() async {
  final res = await http.get(
    Uri.parse('$_authEmu/emulator/v1/projects/$_project/accounts'),
    headers: const {'Authorization': 'Bearer owner'},
  );
  final users = (jsonDecode(res.body) as Map<String, dynamic>)['userInfo'] as List<dynamic>?;
  return users?.length ?? 0;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  tearDown(() => AuthService.debugTokenFetcher = null);

  testWidgets('DEAD credential: deleted account recovers to a working session',
      (tester) async {
    await AuthService.instance.signOut();
    final firstUid = (await AuthService.instance.initAuth()).uid;
    expect(FirebaseAuth.instance.currentUser, isNotNull);

    // Server-side deletion. The client still holds the session.
    await deleteAllAccountsServerSide();
    expect(await accountCount(), 0);
    expect(FirebaseAuth.instance.currentUser?.uid, firstUid,
        reason: 'client should still *believe* it is signed in — that is the bug');

    // Simulate a COLD START with the dead session still in the keychain.
    // signOut() must NOT be used here: it clears currentUser and would leave
    // initAuth() doing an ordinary fresh sign-in, which passes even without
    // the fix. Only the memo is dropped.
    AuthService.instance.debugResetMemo();
    expect(FirebaseAuth.instance.currentUser?.uid, firstUid,
        reason: 'the dead cached session must still be in place');

    // Reach the moment the cached token expires and must refresh.
    FirebaseAuthException? observed;
    AuthService.debugTokenFetcher = (u) async {
      try {
        return await u.getIdToken(true);
      } on FirebaseAuthException catch (e) {
        observed = e;
        rethrow;
      }
    };
    final recovered = await AuthService.instance.initAuth();
    expect(observed, isNotNull, reason: 'the refresh must have genuinely failed');
    expect(AuthService.deadCredentialCodes, contains(observed!.code),
        reason: 'real SDK code for a deleted account: ${observed!.code}');

    expect(recovered.uid, isNot(firstUid), reason: 'must be a NEW session');
    expect(recovered.isAnonymous, isTrue);

    // The recovered session must actually work, not merely exist.
    AuthService.debugTokenFetcher = null;
    final token = await recovered.getIdToken();
    expect(token, isNotNull);
    expect(token!.length, greaterThan(0));

    // Server-sourced read of a collection the rules DO gate on signedIn()
    // (firestore.rules: `match /users/{userId} { allow read: if signedIn(); }`).
    // It only succeeds if the recovered credential actually authenticates.
    final probe = await FirebaseFirestore.instance
        .collection('users')
        .limit(1)
        .get(const GetOptions(source: Source.server));
    expect(probe.metadata.isFromCache, isFalse,
        reason: 'recovered session must reach the server, not fall back to cache');
  });

  testWidgets('TRANSIENT failure: wifi drop must NOT sign the user out',
      (tester) async {
    await AuthService.instance.signOut();
    final uid = (await AuthService.instance.initAuth()).uid;

    for (final code in ['network-request-failed', 'too-many-requests', 'some-future-sdk-code']) {
      AuthService.debugTokenFetcher =
          (u) => Future<String?>.error(FirebaseAuthException(code: code));
      await AuthService.instance.signOut();
      // signOut clears currentUser, so re-establish the cached-session state.
      await FirebaseAuth.instance.signInAnonymously();
      final cachedUid = FirebaseAuth.instance.currentUser!.uid;

      final kept = await AuthService.instance.initAuth();
      expect(kept.uid, cachedUid, reason: '[$code] must keep the SAME session');
      expect(FirebaseAuth.instance.currentUser, isNotNull,
          reason: '[$code] must not sign the user out');
    }

    // A timeout is transient too.
    AuthService.debugTokenFetcher =
        (u) => Future<String?>.delayed(const Duration(seconds: 30), () => 'never');
    await AuthService.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();
    final beforeUid = FirebaseAuth.instance.currentUser!.uid;
    final keptAfterTimeout = await AuthService.instance.initAuth();
    expect(keptAfterTimeout.uid, beforeUid, reason: 'timeout must keep the session');
    expect(uid, isNotNull);
  }, timeout: const Timeout(Duration(seconds: 90)));

  testWidgets('FAST PATH: a valid cached token does no network round trip',
      (tester) async {
    await AuthService.instance.signOut();
    await AuthService.instance.initAuth();
    await AuthService.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();

    var fetches = 0;
    AuthService.debugTokenFetcher = (u) {
      fetches++;
      return u.getIdToken(); // non-forced: cache hit, no network
    };
    final sw = Stopwatch()..start();
    await AuthService.instance.initAuth();
    sw.stop();

    expect(fetches, 1, reason: 'validation runs exactly once per launch');
    expect(sw.elapsedMilliseconds, lessThan(1000),
        reason: 'valid cached token must not wait on the network');
  });
}
