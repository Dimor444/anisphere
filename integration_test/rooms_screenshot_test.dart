// One-off screenshot capture for the Watch Party section of Community > Rooms
// and the new Room Detail screen — run with flutter drive so the driver saves
// PNGs (see test_driver/integration_test.dart).
//
// REQUIRES the functions emulator: the member counts in these shots are
// produced by the real memberCount trigger, not seeded directly. Each room is
// created with memberCount 0, then given that many real member docs; the
// trigger recomputes the count from the subcollection, and we poll until it
// converges before capturing. If the functions emulator isn't up, the counts
// never move off 0 and the poll fails loudly.
//
// Captures:
//  1. Rooms tab — Watch Party card streaming live rooms, live ones first.
//  2. Create Room sheet — title, optional AniList anime, optional episode.
//  3. Room Detail — title, live member count, "coming soon" placeholder.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/core/theme/app_theme.dart';
import 'package:anisphere/features/community/community_screen.dart';
import 'package:anisphere/features/community/room_detail_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';

const _base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
const _ownerHeaders = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

/// Wipes the rooms collection so a rerun doesn't stack leftovers from
/// rooms_rules_test.dart into the shot.
Future<void> _clearRooms() async {
  final res = await http.get(Uri.parse('$_base/rooms?pageSize=300'), headers: _ownerHeaders);
  final docs = (jsonDecode(res.body) as Map<String, dynamic>)['documents'] as List<dynamic>?;
  for (final d in docs ?? const []) {
    await http.delete(Uri.parse('http://localhost:8080/v1/${(d as Map)['name']}'), headers: _ownerHeaders);
  }
}

/// Builds a room whose memberCount is produced by the REAL trigger.
///
/// Writes the room doc with memberCount 0, then adds [memberCount] real member
/// docs — each fires onRoomMemberJoined, which recomputes the count from the
/// subcollection. Polls until the count converges, so the number in the shot
/// is the trigger's output, not a value we set. (createdAt is backdated only
/// to control list ordering; the trigger touches memberCount alone.)
Future<void> _buildRoom(
  String id, {
  required String title,
  required String hostUid,
  required int memberCount,
  required bool isLive,
  String? animeId,
  int? episodeNumber,
  required Duration age,
}) async {
  final roomRes = await http.patch(
    Uri.parse('$_base/rooms/$id'),
    headers: _ownerHeaders,
    body: jsonEncode({
      'fields': {
        'type': {'stringValue': 'watch_party'},
        'title': {'stringValue': title},
        'hostUid': {'stringValue': hostUid},
        'memberCount': {'integerValue': '0'},
        'isLive': {'booleanValue': isLive},
        if (animeId != null) 'animeId': {'stringValue': animeId},
        if (episodeNumber != null) 'episodeNumber': {'integerValue': '$episodeNumber'},
        'createdAt': {
          'timestampValue': DateTime.now().toUtc().subtract(age).toIso8601String(),
        },
      },
    }),
  );
  expect(roomRes.statusCode, 200, reason: 'room write failed: ${roomRes.body}');

  // Deleting a room doc does NOT delete its members subcollection, so a rerun
  // would otherwise stack stale member docs and inflate the count. Clear first.
  final existing = await http.get(Uri.parse('$_base/rooms/$id/members?pageSize=300'), headers: _ownerHeaders);
  for (final d in (jsonDecode(existing.body) as Map<String, dynamic>)['documents'] as List<dynamic>? ?? const []) {
    await http.delete(Uri.parse('http://localhost:8080/v1/${(d as Map)['name']}'), headers: _ownerHeaders);
  }

  // Deterministic member ids so the count is exactly [memberCount] on rerun.
  for (var i = 0; i < memberCount; i++) {
    final m = await http.patch(
      Uri.parse('$_base/rooms/$id/members/${id}_m$i'),
      headers: _ownerHeaders,
      body: jsonEncode({
        'fields': {
          'joinedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        },
      }),
    );
    expect(m.statusCode, 200, reason: 'member write failed: ${m.body}');
  }

  // Wait for the trigger to catch up to the real member count.
  final ref = FirebaseFirestore.instance.collection('rooms').doc(id);
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  var seen = -1;
  while (DateTime.now().isBefore(deadline)) {
    seen = ((await ref.get()).data()?['memberCount'] as num?)?.toInt() ?? -1;
    if (seen == memberCount) break;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  expect(seen, memberCount,
      reason: 'trigger never drove memberCount to $memberCount for $id '
          '(is the functions emulator running?)');
}

Future<void> pumpFor(WidgetTester tester, Duration total) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  });

  testWidgets('capture: Rooms tab + create sheet + room detail', (tester) async {
    await AuthService.instance.signOut();
    final uid = (await AuthService.instance.initAuth()).uid;

    await _clearRooms();
    // Counts below are produced by the trigger from real member docs.
    // Real AniList id for Frieren so the id-only link is realistic.
    await _buildRoom('zz_frieren', title: 'Frieren ep 28', hostUid: uid, memberCount: 14, isLive: true, animeId: '154587', episodeNumber: 28, age: const Duration(minutes: 3));
    await _buildRoom('zz_jjk', title: 'JJK rewatch', hostUid: 'zzhost2', memberCount: 6, isLive: true, age: const Duration(minutes: 40));
    await _buildRoom('zz_op', title: 'One Piece marathon', hostUid: 'zzhost3', memberCount: 23, isLive: true, episodeNumber: 1071, age: const Duration(hours: 2));
    await _buildRoom('zz_vinland', title: 'Vinland Saga — ended', hostUid: 'zzhost4', memberCount: 0, isLive: false, age: const Duration(hours: 5));

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: const CommunityScreen()),
    ));
    await pumpFor(tester, const Duration(seconds: 6));
    await binding.takeScreenshot('rooms_tab_watch_party');

    // ── Create Room sheet
    await tester.tap(find.text('Create Room +'));
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.enterText(find.widgetWithText(TextField, 'Room title').first, 'Frieren ep 29');
    await pumpFor(tester, const Duration(seconds: 1));
    await binding.takeScreenshot('rooms_create_sheet');
  });

  // Drives the sheet the way a user does: search AniList, pick a result, submit
  // — proving the picked anime lands as an id and the creator is joined. Needs
  // live AniList; skipped rather than failed when the network is unavailable.
  testWidgets('create flow attaches the picked AniList id', (tester) async {
    final uid = (await AuthService.instance.initAuth()).uid;

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: const CommunityScreen()),
    ));
    await pumpFor(tester, const Duration(seconds: 4));

    await tester.tap(find.text('Create Room +'));
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.enterText(find.widgetWithText(TextField, 'Room title').first, 'ZZ Search Room');
    await tester.enterText(find.widgetWithText(TextField, 'Anime (optional)').first, 'Frieren');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFor(tester, const Duration(seconds: 8));

    final firstResult = find.byType(ListTile);
    if (firstResult.evaluate().isEmpty) {
      markTestSkipped('AniList unreachable — search picker not exercised');
      return;
    }
    await tester.tap(firstResult.first);
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.enterText(find.widgetWithText(TextField, 'Episode number (optional)').first, '29');
    await pumpFor(tester, const Duration(seconds: 1));
    await binding.takeScreenshot('rooms_create_sheet_anime_picked');

    await tester.tap(find.text('Create Room'));
    await pumpFor(tester, const Duration(seconds: 5));

    final snap = await FirebaseFirestore.instance
        .collection('rooms')
        .where('title', isEqualTo: 'ZZ Search Room')
        .get();
    expect(snap.docs, hasLength(1));
    final data = snap.docs.single.data();
    expect(data['animeId'], isA<String>(), reason: 'AniList id attached from the picker');
    expect(int.tryParse(data['animeId'] as String), isNotNull, reason: 'id-only, no title text');
    expect(data['episodeNumber'], 29);
    expect(data['hostUid'], uid);

    final members = await snap.docs.single.reference.collection('members').get();
    expect(members.docs.map((d) => d.id), [uid], reason: 'creator joined — fires the trigger');

    // The trigger is live, so the creator's join drives memberCount 0 → 1.
    // Poll: the count settles a beat after the join lands.
    final ref = snap.docs.single.reference;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var count = -1;
    while (DateTime.now().isBefore(deadline)) {
      count = ((await ref.get()).data()?['memberCount'] as num?)?.toInt() ?? -1;
      if (count == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(count, 1, reason: 'trigger drives the creator-join to memberCount 1');
  });

  testWidgets('room detail renders the server-owned count', (tester) async {
    // Fresh tree — the previous test's modal route would otherwise sit on top.
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: const RoomDetailScreen(roomId: 'zz_frieren')),
    ));
    await pumpFor(tester, const Duration(seconds: 4));
    expect(find.text('Frieren ep 28'), findsOneWidget);
    expect(find.text('14 watching'), findsOneWidget);
    await binding.takeScreenshot('room_detail');
  });
}
