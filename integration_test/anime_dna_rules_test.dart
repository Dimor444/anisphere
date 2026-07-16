import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/anime_dna_service.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/follow_service.dart';
import 'package:anisphere/services/my_list_service.dart';

/// Anime DNA rules + derivation against the emulator:
///  - dnaPinned / firstAnimeId save and read back (ids only);
///  - invalid payloads and denormalized keys are denied;
///  - a DNA write can never smuggle isVerified / currency / counter /
///    streak fields (the ensureProfile-seeded-isVerified class of bug);
///  - docs without DNA fields keep passing profile edits (regression);
///  - two users with different lists derive DIFFERENT card slots, and an
///    empty list yields the empty state, never sample data.
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

  Future<String> freshUser() async {
    await AuthService.instance.signOut();
    final uid = (await AuthService.instance.initAuth()).uid;
    await FollowService.instance.ensureProfile(); // placeholder handle
    return uid;
  }

  DocumentReference<Map<String, dynamic>> userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  testWidgets('DNA overrides save, read back, and clear', (tester) async {
    final uid = await freshUser();

    await AnimeDnaService.instance.setPinned([16498, 101922, 21]);
    var d = (await userDoc(uid).get()).data()!;
    expect(d['dnaPinned'], [16498, 101922, 21]);

    await AnimeDnaService.instance.setFirstAnime(20);
    d = (await userDoc(uid).get()).data()!;
    expect(d['firstAnimeId'], 20);
    expect(d['dnaPinned'], [16498, 101922, 21], reason: 'first-anime write leaves pins alone');

    // Unpin-all → empty list persists (fully derived again).
    await AnimeDnaService.instance.setPinned([]);
    d = (await userDoc(uid).get()).data()!;
    expect(d['dnaPinned'], isEmpty);

    // The service clamp: >5 pins are capped client-side before the write.
    await AnimeDnaService.instance.setPinned([1, 2, 3, 4, 5, 6, 7]);
    d = (await userDoc(uid).get()).data()!;
    expect(d['dnaPinned'], [1, 2, 3, 4, 5]);
  });

  testWidgets('invalid DNA payloads and denormalized keys are denied', (tester) async {
    final uid = await freshUser();
    final doc = userDoc(uid);

    // Raw writes around the service clamp: the rules are the enforcement.
    await expectLater(doc.update({'dnaPinned': [1, 2, 3, 4, 5, 6]}), _denied);
    await expectLater(doc.update({'dnaPinned': [0]}), _denied);
    await expectLater(doc.update({'dnaPinned': [-5]}), _denied);
    await expectLater(doc.update({'dnaPinned': ['16498']}), _denied);
    await expectLater(doc.update({'dnaPinned': 16498}), _denied);
    await expectLater(doc.update({'firstAnimeId': 0}), _denied);
    await expectLater(doc.update({'firstAnimeId': -1}), _denied);
    await expectLater(doc.update({'firstAnimeId': 'Naruto'}), _denied);

    // Never copy AniList data: any denormalized key is rejected.
    await expectLater(doc.update({'dnaPinned': [1], 'dnaTitles': ['Frieren']}), _denied);
    await expectLater(doc.update({'dnaPinned': [1], 'dnaCovers': ['https://x/y.jpg']}), _denied);
    await expectLater(doc.update({'firstAnime': 'Naruto (2007)'}), _denied);
    await expectLater(doc.update({'dnaGenres': ['Action']}), _denied);

    final d = (await doc.get()).data()!;
    expect(d.containsKey('dnaPinned'), isFalse, reason: 'no denied write leaked through');
    expect(d.containsKey('firstAnimeId'), isFalse);
  });

  testWidgets('DNA writes cannot smuggle sensitive fields', (tester) async {
    final uid = await freshUser();
    final doc = userDoc(uid);

    // Verification, currencies, counters, streaks — alongside a DNA field.
    await expectLater(doc.update({'dnaPinned': [1], 'isVerified': true}), _denied);
    await expectLater(doc.update({'firstAnimeId': 20, 'aniGold': 999999}), _denied);
    await expectLater(doc.update({'dnaPinned': [1], 'aniGem': 999999}), _denied);
    await expectLater(doc.update({'dnaPinned': [1], 'followerCount': 9999}), _denied);
    await expectLater(doc.update({'firstAnimeId': 20, 'postsCount': 9999}), _denied);
    await expectLater(doc.update({'dnaPinned': [1], 'currentStreak': 999}), _denied);
    await expectLater(doc.update({'dnaPinned': [1], 'longestStreak': 999}), _denied);
    // And alone, for completeness.
    await expectLater(doc.update({'isVerified': true}), _denied);
    await expectLater(doc.update({'aniGold': 1}), _denied);

    final d = (await doc.get()).data()!;
    expect(d['isVerified'], isFalse);
    expect(d.containsKey('aniGold'), isFalse);
    expect(d['followerCount'], 0);
    expect(d.containsKey('dnaPinned'), isFalse, reason: 'denied batches leave nothing behind');
  });

  testWidgets('docs without DNA fields still pass profile edits (regression)', (tester) async {
    final uid = await freshUser();

    // Fresh doc, no DNA fields — the pre-DNA path must work byte-for-byte.
    await FollowService.instance.updateProfile(displayName: 'DNA Regression', bio: 'still fine');
    var d = (await userDoc(uid).get()).data()!;
    expect(d['displayName'], 'DNA Regression');

    // And after DNA fields exist, plain profile edits keep passing.
    await AnimeDnaService.instance.setPinned([16498]);
    await AnimeDnaService.instance.setFirstAnime(20);
    await FollowService.instance.updateProfile(displayName: 'DNA Regression 2', bio: 'still fine');
    d = (await userDoc(uid).get()).data()!;
    expect(d['displayName'], 'DNA Regression 2');
    expect(d['dnaPinned'], [16498]);
    expect(d['firstAnimeId'], 20);
  });

  testWidgets('two users derive DIFFERENT DNA; empty list yields empty state', (tester) async {
    // User A: loves 16498 (scored 10) over 21 (scored 6).
    final uidA = await freshUser();
    await MyListService.instance.addToMyList(16498, 'A-16498', '', ListStatus.completed);
    await MyListService.instance.updateScore(16498, 10);
    await MyListService.instance.addToMyList(21, 'A-21', '', ListStatus.current);
    await MyListService.instance.updateScore(21, 6);
    final entriesA = await FirebaseFirestore.instance
        .collection('users').doc(uidA).collection('myList').get();
    final idsA = AnimeDnaService.deriveCardIds(
      entries: entriesA.docs.map(MyListEntry.fromDoc).toList(),
      pinned: const [],
    );
    expect(idsA, [16498, 21]);

    // Pinning overrides derivation; unpinning restores it.
    expect(
      AnimeDnaService.deriveCardIds(
        entries: entriesA.docs.map(MyListEntry.fromDoc).toList(),
        pinned: const [21],
      ),
      [21, 16498],
      reason: 'pin takes the first slot over the higher-rated derived pick',
    );

    // User B: different list, opposite scores → different DNA.
    final uidB = await freshUser();
    await MyListService.instance.addToMyList(101922, 'B-101922', '', ListStatus.completed);
    await MyListService.instance.updateScore(101922, 9);
    await MyListService.instance.addToMyList(20, 'B-20', '', ListStatus.completed);
    final entriesB = await FirebaseFirestore.instance
        .collection('users').doc(uidB).collection('myList').get();
    final idsB = AnimeDnaService.deriveCardIds(
      entries: entriesB.docs.map(MyListEntry.fromDoc).toList(),
      pinned: const [],
    );
    expect(idsB, [101922, 20]);
    expect(idsB, isNot(equals(idsA)), reason: 'no more identical DNA for everyone');

    // User C: empty list, no overrides → structurally empty DNA (the widget
    // renders the invite box off this, never fake cards). No AniList request
    // is needed for an empty id set, so this is deterministic offline.
    final uidC = await freshUser();
    final dna = await AnimeDnaService.instance.fetchDna(
      uid: uidC,
      pinned: const [],
      firstAnimeId: null,
    );
    expect(dna.isEmpty, isTrue);
    expect(dna.cards, isEmpty);
    expect(dna.topGenres, isEmpty);
    expect(dna.firstAnime, isNull);
    expect(dna.listSize, 0);
  });
}
