// The memberCount Cloud Function trigger, exercised for real against the
// emulator suite (auth + firestore + FUNCTIONS — the functions emulator must
// be running or every expectation here times out).
//
// Everything asserts on the room doc as READ BACK after the trigger settles,
// never on write intent: memberCount is server-owned, so the client's write is
// only the stimulus.
//
// At-least-once redelivery (the same event invoking the handler twice, or a
// stale create arriving after its delete) is NOT reachable by driving
// Firestore — a no-op delete emits no event. Those cases are covered by
// calling the handler body directly in functions/test/member_count.test.js.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/room_service.dart';

const _base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';

/// Removes a member doc as admin ("Bearer owner" bypasses rules on the
/// emulator). Used only where the real user's session is unreachable — the
/// trigger fires on the delete either way.
Future<void> _adminDeleteMember(String roomId, String uid) async {
  final res = await http.delete(
    Uri.parse('$_base/rooms/$roomId/members/$uid'),
    headers: const {'Authorization': 'Bearer owner'},
  );
  expect(res.statusCode, 200, reason: 'admin delete failed: ${res.body}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  DocumentReference<Map<String, dynamic>> roomRef(String id) =>
      FirebaseFirestore.instance.collection('rooms').doc(id);

  Future<int> readCount(String id) async =>
      ((await roomRef(id).get()).data()?['memberCount'] as num?)?.toInt() ?? -999;

  /// Polls the room doc until memberCount reaches [expected], then holds to
  /// make sure it SETTLES there rather than sailing past. Fails loudly on
  /// timeout — a silent pass would defeat the point of this file.
  Future<void> expectCountSettles(String id, int expected, {String? reason}) async {
    const timeout = Duration(seconds: 20);
    final deadline = DateTime.now().add(timeout);
    var last = await readCount(id);
    while (DateTime.now().isBefore(deadline)) {
      last = await readCount(id);
      if (last == expected) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(last, expected,
        reason: reason ?? 'memberCount never reached $expected within ${timeout.inSeconds}s '
            '(is the functions emulator running?)');

    // Hold: catches a double-bump landing a beat later.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(await readCount(id), expected, reason: 'memberCount did not settle at $expected');
  }

  Future<String> freshUser() async {
    await AuthService.instance.signOut();
    return (await AuthService.instance.initAuth()).uid;
  }

  testWidgets('join/leave cycle drives memberCount 1 → 2 → 1 → 0', (tester) async {
    // ── A creates the room; createWatchParty joins the host.
    final uidA = await freshUser();
    final roomId = await RoomService.instance.createWatchParty(title: 'ZZ Trigger Room');
    await expectCountSettles(roomId, 1, reason: 'host auto-join should bump 0 → 1');

    // ── B joins.
    final uidB = await freshUser();
    expect(uidB, isNot(uidA));
    await RoomService.instance.joinRoom(roomId);
    await expectCountSettles(roomId, 2, reason: 'second member should bump 1 → 2');

    // ── B leaves.
    await RoomService.instance.leaveRoom(roomId);
    await expectCountSettles(roomId, 1, reason: 'B leaving should drop 2 → 1');

    // ── A leaves. There's no way back into A's session — anonymous re-auth
    // mints a fresh uid, and rules (correctly) deny deleting someone else's
    // membership. So remove A's doc through the emulator's admin endpoint;
    // the trigger fires on the delete regardless of who issued it.
    await _adminDeleteMember(roomId, uidA);
    await expectCountSettles(roomId, 0, reason: 'last member leaving should drop 1 → 0');
  });

  testWidgets('deleting an already-absent member doc leaves the count alone', (tester) async {
    final uid = await freshUser();
    final roomId = await RoomService.instance.createWatchParty(title: 'ZZ Idempotent Room');
    await expectCountSettles(roomId, 1);

    await RoomService.instance.leaveRoom(roomId);
    await expectCountSettles(roomId, 0);

    // Second delete of the same (now absent) doc. Firestore emits no delete
    // event for a no-op delete, so the handler never runs and the counter
    // holds. (Redelivery — where it DOES run again — is member_count.test.js.)
    await roomRef(roomId).collection('members').doc(uid).delete();
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(await readCount(roomId), 0, reason: 'no-op delete must not push memberCount negative');
  });
}
