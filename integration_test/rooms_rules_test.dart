import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/data/models/room.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/room_service.dart';

/// Watch Party rooms against the emulator:
///  - a room round-trips (ids only for the anime link, never denormalized
///    AniList data), and the creator lands in members/;
///  - memberCount is server-owned: no client write may seed it non-zero,
///    bump it, or smuggle it in alongside a legal field edit;
///  - hostUid cannot be forged, and non-hosts cannot edit/delete a room;
///  - membership is self-keyed: nobody may join or leave as someone else.
///
/// The memberCount VALUE is not asserted here — the Cloud Function trigger
/// that owns it needs the functions emulator (and Node). This file pins the
/// rules boundary, which is what keeps the counter honest.
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

  // Resolved lazily — FirebaseFirestore.instance would throw at main() time,
  // before setUpAll has initialized the app.
  CollectionReference<Map<String, dynamic>> rooms() =>
      FirebaseFirestore.instance.collection('rooms');

  Future<String> freshUser() async {
    await AuthService.instance.signOut();
    return (await AuthService.instance.initAuth()).uid;
  }

  testWidgets('room round-trips and the creator is a member', (tester) async {
    final uid = await freshUser();

    final id = await RoomService.instance.createWatchParty(
      title: 'Frieren ep 28',
      animeId: '154587',
      episodeNumber: 28,
    );

    final room = Room.fromDoc(await rooms().doc(id).get());
    expect(room.type, Room.typeWatchParty);
    expect(room.title, 'Frieren ep 28');
    expect(room.animeId, '154587', reason: 'AniList id only — no title/cover denormalized');
    expect(room.episodeNumber, 28);
    expect(room.hostUid, uid);
    expect(room.isLive, isTrue);
    expect(room.createdAt, isNotNull);

    final member = await rooms().doc(id).collection('members').doc(uid).get();
    expect(member.exists, isTrue, reason: 'creator is joined — this is what fires the trigger');
    expect(member.data()!.keys, ['joinedAt']);

    // The create payload never carries AniList text — cover/title are fetched live.
    final raw = (await rooms().doc(id).get()).data()!;
    expect(raw.containsKey('animeTitle'), isFalse);
    expect(raw.containsKey('animeCover'), isFalse);
  });

  testWidgets('optional fields may be omitted entirely', (tester) async {
    await freshUser();
    final id = await RoomService.instance.createWatchParty(title: 'JJK rewatch');
    final raw = (await rooms().doc(id).get()).data()!;
    expect(raw.containsKey('animeId'), isFalse);
    expect(raw.containsKey('episodeNumber'), isFalse);
    expect(Room.fromDoc(await rooms().doc(id).get()).memberCount, 0);
  });

  testWidgets('memberCount is not client-writable', (tester) async {
    final uid = await freshUser();
    final id = await RoomService.instance.createWatchParty(title: 'One Piece marathon');

    // Seeded non-zero at create.
    await expectLater(
      rooms().add({
        'type': Room.typeWatchParty,
        'title': 'Cheater',
        'hostUid': uid,
        'memberCount': 500,
        'isLive': true,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      _denied,
    );

    // Bumped directly by the host.
    await expectLater(rooms().doc(id).update({'memberCount': 99}), _denied);
    await expectLater(rooms().doc(id).update({'memberCount': FieldValue.increment(1)}), _denied);

    // Smuggled in next to a legal edit.
    await expectLater(rooms().doc(id).update({'title': 'New title', 'memberCount': 42}), _denied);

    // The legal edit alone still works.
    await rooms().doc(id).update({'title': 'New title', 'isLive': false});
    final room = Room.fromDoc(await rooms().doc(id).get());
    expect(room.title, 'New title');
    expect(room.isLive, isFalse);
    expect(room.memberCount, 0, reason: 'still untouched by any client write');
  });

  testWidgets('hostUid cannot be forged, and non-hosts cannot edit', (tester) async {
    final hostUid = await freshUser();
    final id = await RoomService.instance.createWatchParty(title: 'Host room');

    // A second user cannot claim someone else as host...
    await freshUser();
    await expectLater(
      rooms().add({
        'type': Room.typeWatchParty,
        'title': 'Impersonation',
        'hostUid': hostUid,
        'memberCount': 0,
        'isLive': true,
        'createdAt': FieldValue.serverTimestamp(),
      }),
      _denied,
    );

    // ...nor edit or delete a room they don't host.
    await expectLater(rooms().doc(id).update({'title': 'Hijacked'}), _denied);
    await expectLater(rooms().doc(id).delete(), _denied);
  });

  testWidgets('membership is self-keyed; join and leave are the only moves', (tester) async {
    final hostUid = await freshUser();
    final id = await RoomService.instance.createWatchParty(title: 'Roster room');

    final joinerUid = await freshUser();
    await RoomService.instance.joinRoom(id);
    expect((await rooms().doc(id).collection('members').doc(joinerUid).get()).exists, isTrue);

    // Re-joining is a no-op rather than a denied update (and can't double-bump).
    await RoomService.instance.joinRoom(id);

    // Cannot join, edit, or evict as somebody else.
    final members = rooms().doc(id).collection('members');
    await expectLater(
      members.doc(hostUid).set({'joinedAt': FieldValue.serverTimestamp()}),
      _denied,
    );
    await expectLater(members.doc(hostUid).delete(), _denied);
    await expectLater(members.doc(joinerUid).update({'joinedAt': FieldValue.serverTimestamp()}), _denied);

    // Forged join timestamps are rejected — joinedAt must be the server's.
    await freshUser();
    await expectLater(
      members.doc(FirebaseAuth.instance.currentUser!.uid).set({'joinedAt': Timestamp.fromDate(DateTime(2020))}),
      _denied,
    );

    // Leaving your own membership works.
    await AuthService.instance.signOut();
    await FirebaseAuth.instance.signInAnonymously();
    await RoomService.instance.leaveRoom(id); // not a member — delete of a missing doc is fine
  });

  testWidgets('the watch-party stream is ordered live-first, newest-first', (tester) async {
    await freshUser();
    final oldId = await RoomService.instance.createWatchParty(title: 'Older live');
    final deadId = await RoomService.instance.createWatchParty(title: 'Ended');
    await rooms().doc(deadId).update({'isLive': false});
    final newId = await RoomService.instance.createWatchParty(title: 'Newest live');

    final list = await RoomService.instance.watchPartyRooms().first;
    final ids = list.map((r) => r.id).toList();
    expect(ids.contains(newId) && ids.contains(oldId) && ids.contains(deadId), isTrue);
    expect(ids.indexOf(newId) < ids.indexOf(oldId), isTrue, reason: 'newer live room sorts first');
    expect(ids.indexOf(oldId) < ids.indexOf(deadId), isTrue, reason: 'live rooms outrank ended ones');
  });
}
