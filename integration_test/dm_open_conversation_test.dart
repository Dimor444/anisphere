import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/data/models/dm_conversation.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/dm_service.dart';

/// Opening a DM thread through the REAL Dart service, against the emulator.
///
/// This file exists because of a production escape: every earlier DM test
/// drove `setDoc` through the JS rules-unit-testing SDK, and every simulator
/// run opened a PRE-SEEDED thread. Nothing ever called
/// [DmService.openConversation] with no document at the target id — which is
/// the one path a first "Message" tap always takes. It failed in production
/// with permission-denied: the conversations read rule is
/// `request.auth.uid in resource.data.participants`, and for a missing
/// document `resource` is null, so the pre-read that guarded the create was
/// itself denied.
///
/// The lesson these tests encode: exercise the service method, not a
/// hand-written equivalent of what you think it does.
final _denied =
    throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  CollectionReference<Map<String, dynamic>> conversations() =>
      FirebaseFirestore.instance.collection('conversations');

  Future<String> freshUser() async {
    await AuthService.instance.signOut();
    return (await AuthService.instance.initAuth()).uid;
  }

  testWidgets('opens a thread when NO document exists yet (the escaped bug)',
      (tester) async {
    final me = await freshUser();
    // A counterpart uid that is merely a string here: the first tap on
    // someone's Message button never has a conversation doc waiting.
    const other = 'zzOpenConvNobody01';

    final cid = await DmService.instance.openConversation(other);

    expect(cid, DmConversation.cidFor(me, other));
    final doc = await conversations().doc(cid).get();
    expect(doc.exists, isTrue, reason: 'the first open must create the thread');
    final convo = DmConversation.fromDoc(doc);
    expect(convo.participants, [me, other]..sort());
    expect(convo.lastMessage, '', reason: 'born empty');
    expect(convo.blockedBy, isEmpty);
    expect(convo.lastReadAt, isEmpty);
    expect(convo.createdAt, isNotNull, reason: 'server-stamped');
  });

  testWidgets('called twice: one doc, no throw, same cid', (tester) async {
    final me = await freshUser();
    const other = 'zzOpenConvNobody02';

    final first = await DmService.instance.openConversation(other);
    final createdAt = DmConversation.fromDoc(await conversations().doc(first).get()).createdAt;

    // The second call must be a no-op that still reports success — the
    // caller asked for "the thread with this person", and it exists.
    final second = await DmService.instance.openConversation(other);
    expect(second, first, reason: 'deterministic cid');

    final after = await conversations().doc(first).get();
    expect(after.exists, isTrue);
    expect(DmConversation.fromDoc(after).createdAt, createdAt,
        reason: 'the second call must not rewrite the doc');

    // Exactly one thread for this pair — nothing duplicated under another id.
    final mine = await conversations().where('participants', arrayContains: me).get();
    expect(mine.docs.length, 1);
  });

  testWidgets('a non-participant still cannot create at someone else\'s cid',
      (tester) async {
    // Boundary guard, not a bug-catcher: this passes with or without the fix.
    // It is here so that loosening the client can never quietly loosen who is
    // allowed to open a thread.
    const a = 'zzOpenConvStrangerA';
    const b = 'zzOpenConvStrangerB';
    final cid = DmConversation.cidFor(a, b);
    await freshUser(); // signed in, but not a participant

    await expectLater(
      conversations().doc(cid).set({
        'participants': [a, b]..sort(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastSenderId': '',
        'lastReadAt': <String, dynamic>{},
        'blockedBy': <String>[],
      }),
      _denied,
    );
  });

  testWidgets('self-DM is refused before any write', (tester) async {
    final me = await freshUser();
    await expectLater(
        DmService.instance.openConversation(me), throwsA(isA<ArgumentError>()));
  });
}
