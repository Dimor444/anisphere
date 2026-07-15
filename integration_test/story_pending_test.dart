import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/features/stories/story_providers.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/story_service.dart';

const _base = 'http://localhost:8080/v1/projects/anisphere-36cb0/databases/(default)/documents';
const _ownerHeaders = {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'};

/// Owner-credential seed of an already-synced story from another user, so the
/// listener has server data before the offline write under test.
Future<void> _seedStory(String id, String uid, DateTime createdAt) async {
  final res = await http.patch(
    Uri.parse('$_base/stories/$id'),
    headers: _ownerHeaders,
    body: jsonEncode({
      'fields': {
        'uid': {'stringValue': uid},
        'mediaUrl': {'stringValue': 'https://example.com/seed.jpg'},
        'createdAt': {'timestampValue': createdAt.toUtc().toIso8601String()},
        'expiresAt': {'timestampValue': createdAt.add(const Duration(hours: 24)).toUtc().toIso8601String()},
      },
    }),
  );
  expect(res.statusCode, 200, reason: 'seed story failed: ${res.body}');
}

Future<void> _deleteStory(String id) async {
  await http.delete(Uri.parse('$_base/stories/$id'), headers: _ownerHeaders);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String uid;
  const seedId = 'zz-pending-test-seed';

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Emulator suite only — never production data.
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);

    await AuthService.instance.signOut();
    uid = (await AuthService.instance.initAuth()).uid;
    await _seedStory(seedId, 'zz-other-user', DateTime.now().subtract(const Duration(hours: 1)));
  });

  tearDownAll(() async {
    await FirebaseFirestore.instance.enableNetwork();
    await _deleteStory(seedId);
  });

  testWidgets('freshly-written story (pending serverTimestamp) appears immediately', (tester) async {
    final db = FirebaseFirestore.instance;
    final doc = db.collection('stories').doc();

    // Layer 1 — the raw ring query, exactly as getActiveStories builds it.
    // Records membership + pending metadata per emission for diagnosis.
    final rawLog = <String>[];
    final rawSeen = Completer<void>();
    final rawSub = db
        .collection('stories')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
      final entry = snap.docs
          .map((d) => '${d.id}(pending=${d.metadata.hasPendingWrites},'
              'createdAtNull=${d.data()['createdAt'] == null})')
          .join(' ');
      rawLog.add(entry);
      if (snap.docs.any((d) => d.id == doc.id) && !rawSeen.isCompleted) rawSeen.complete();
    });

    // Layer 2 — the service stream the provider consumes.
    final svcSeen = Completer<void>();
    final svcSub = StoryService.instance.getActiveStories().listen((stories) {
      if (stories.any((s) => s.id == doc.id) && !svcSeen.isCompleted) svcSeen.complete();
    });

    // Layer 3 — the provider that drives the ring.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final groupSeen = Completer<List<StoryGroup>>();
    final provSub = container.listen<AsyncValue<List<StoryGroup>>>(
      activeStoryGroupsProvider,
      (_, next) {
        final groups = next.asData?.value;
        if (groups == null) return;
        final mine = groups.where((g) => g.uid == uid);
        if (mine.isNotEmpty &&
            mine.first.stories.any((s) => s.id == doc.id) &&
            !groupSeen.isCompleted) {
          groupSeen.complete(groups);
        }
      },
      fireImmediately: true,
    );
    addTearDown(provSub.close);
    addTearDown(svcSub.cancel);
    addTearDown(rawSub.cancel);

    // Wait for the initial server sync (seed story visible) before going dark.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(rawLog.join(), contains(seedId), reason: 'listener never synced the seed story');

    // Pin the latency-compensation window open: with the network down the
    // serverTimestamp sentinel never resolves, exactly the on-device moment
    // right after upload.
    await db.disableNetwork();
    addTearDown(db.enableNetwork);

    // The exact write createStory performs (Storage upload is orthogonal).
    // The future only completes on server ack — hold it for the online phase.
    final setFuture = doc.set({
      'uid': uid,
      'mediaUrl': 'https://example.com/pending.jpg',
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
    });
    unawaited(setFuture);

    // Membership in the raw query is the decisive question.
    await rawSeen.future.timeout(const Duration(seconds: 5), onTimeout: () {
      fail('Pending story NEVER entered the local query snapshot. Emissions:\n${rawLog.join('\n')}');
    });
    await svcSeen.future.timeout(const Duration(seconds: 5),
        onTimeout: () => fail('Story missing from getActiveStories while pending'));
    final groups = await groupSeen.future.timeout(const Duration(seconds: 5),
        onTimeout: () => fail('Story missing from activeStoryGroupsProvider while pending'));

    // Ring semantics: my group exists, contains the pending story as latest,
    // and is ordered first (it is the newest story).
    final mine = groups.firstWhere((g) => g.uid == uid);
    expect(mine.latest.id, doc.id, reason: 'pending story must sort as newest in its group');
    expect(groups.first.uid, uid, reason: 'group with the pending story must order first');

    // Back online: the sentinel resolves and the story must survive with a
    // real createdAt (expiry semantics unchanged).
    await db.enableNetwork();
    await setFuture.timeout(const Duration(seconds: 10));
    final resolved = await doc.get();
    expect(resolved.data()!['createdAt'], isNotNull);

    await _deleteStory(doc.id);
  });
}
