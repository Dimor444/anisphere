// Account deletion's decisions, against the AUTH, FIRESTORE and FUNCTIONS
// emulators.
//
// Deletion is done only when the server says so: the deleteAccount callable
// succeeding, or a DEFINITIVE answer that the account is disabled or gone.
// An ambiguous answer — the SDK's catch-all `internal-error` among them —
// never ends the session, before the call or after a failed one: the player
// would believe their account was deleted while nothing on the server was.
//
// "The call failed" is a callable pointed at a port nothing listens on, so no
// request reaches the server. The re-check after it runs through
// AuthService.debugTokenFetcher; where it must be definitive, the account is
// disabled first, which is what the server's own deletion does.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';

const _project = 'anisphere-36cb0';
const _authEmu = 'http://127.0.0.1:9099';
const _firestoreEmu = 'http://127.0.0.1:8080/v1/projects/$_project/databases/(default)/documents';
const _owner = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(region: 'europe-west1');

Future<void> disableServerSide(String uid) async {
  final res = await http.post(
    Uri.parse('$_authEmu/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:update'),
    headers: _owner,
    body: jsonEncode({'localId': uid, 'disableUser': true}),
  );
  expect(res.statusCode, 200, reason: 'emulator disable failed: ${res.body}');
}

/// The account as the auth emulator holds it: null once deleted.
Future<Map<String, dynamic>?> account(String uid) async {
  final res = await http.post(
    Uri.parse('$_authEmu/identitytoolkit.googleapis.com/v1/projects/$_project/accounts:lookup'),
    headers: _owner,
    body: jsonEncode({'localId': [uid]}),
  );
  final users = (jsonDecode(res.body) as Map<String, dynamic>)['users'] as List<dynamic>?;
  return users == null || users.isEmpty ? null : users.first as Map<String, dynamic>;
}

/// Whether the deleteAccount callable started a deletion job for [uid].
Future<bool> deletionJobExists(String uid) async {
  final res = await http.get(Uri.parse('$_firestoreEmu/account_deletions/$uid'), headers: _owner);
  return res.statusCode == 200;
}

Future<String> freshGuest() async {
  await AuthService.instance.signOut();
  return (await AuthService.instance.signInAsGuest()).uid;
}

/// After a deletion that did not end the session, the player is still in.
Future<void> expectStillSignedIn(String uid) async {
  expect(FirebaseAuth.instance.currentUser?.uid, uid);
  expect((await AuthService.instance.initAuth()).uid, uid,
      reason: 'the deliberate sign-out flag must be cleared again');
}

/// After a deletion that ended the session: signed out, and the flag up, so
/// nothing mints a guest behind the player's back.
Future<void> expectSessionEnded() async {
  expect(FirebaseAuth.instance.currentUser, isNull);
  await expectLater(AuthService.instance.initAuth(), throwsA(isA<SignedOutException>()));
}

Matcher deletionFailure(AccountDeletionFailure f) =>
    isA<AccountDeletionException>().having((e) => e.failure, 'failure', f);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
  });

  setUp(() => _functions.useFunctionsEmulator('127.0.0.1', 5001));
  tearDown(() => AuthService.debugTokenFetcher = null);

  testWidgets('before the call, an ambiguous answer sends nothing and keeps the session', (tester) async {
    final uid = await freshGuest();
    AuthService.debugTokenFetcher =
        (u) => Future<String?>.error(FirebaseAuthException(code: 'internal-error'));

    await expectLater(AuthService.instance.deleteAccount(), throwsA(deletionFailure(AccountDeletionFailure.unreachable)));
    AuthService.debugTokenFetcher = null;
    expect(await deletionJobExists(uid), isFalse, reason: 'nothing may reach the server');
    expect((await account(uid))?['disabled'], isNot(true));
    await expectStillSignedIn(uid);
  });

  testWidgets('before the call, a definitive answer ends the session without calling', (tester) async {
    final uid = await freshGuest();
    await disableServerSide(uid); // an earlier attempt committed; its answer never arrived

    await AuthService.instance.deleteAccount();
    expect(await deletionJobExists(uid), isFalse, reason: 'the callable must not be called again');
    await expectSessionEnded();
  });

  testWidgets('a failed call, then an ambiguous answer: unconfirmed, session kept', (tester) async {
    final uid = await freshGuest();
    _functions.useFunctionsEmulator('127.0.0.1', 5999); // nothing listens: the call fails
    var checks = 0;
    AuthService.debugTokenFetcher = (u) {
      checks++;
      return checks == 1
          ? u.getIdToken(true) // the preflight passes
          : Future<String?>.error(FirebaseAuthException(code: 'internal-error'));
    };

    await expectLater(AuthService.instance.deleteAccount(), throwsA(deletionFailure(AccountDeletionFailure.unconfirmed)));
    AuthService.debugTokenFetcher = null;
    expect(checks, 2, reason: 'the failure must be re-checked');
    expect(await deletionJobExists(uid), isFalse);
    await expectStillSignedIn(uid);
  });

  testWidgets('a failed call, then a definitive answer: the server got there, session ended', (tester) async {
    final uid = await freshGuest();
    _functions.useFunctionsEmulator('127.0.0.1', 5999);
    var checks = 0;
    AuthService.debugTokenFetcher = (u) async {
      checks++;
      // The second check stands for the server having committed while its
      // answer was lost: the account is disabled, as the callable does first.
      if (checks == 2) await disableServerSide(uid);
      return u.getIdToken(true);
    };

    await AuthService.instance.deleteAccount();
    expect(checks, 2);
    await expectSessionEnded();
  });

  testWidgets("the callable's success: deleted on the server, session ended", (tester) async {
    final uid = await freshGuest();

    await AuthService.instance.deleteAccount();
    expect(await deletionJobExists(uid), isTrue, reason: 'the server started the deletion');
    final acc = await account(uid);
    expect(acc == null || acc['disabled'] == true, isTrue, reason: 'the account is locked or already gone');
    await expectSessionEnded();
  });
}
