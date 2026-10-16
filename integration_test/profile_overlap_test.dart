import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/feed_service.dart';
import 'package:anisphere/shared/widgets/post_card.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _seed(String path, Map<String, Map<String, dynamic>> fields) async {
  final res = await http.patch(
    Uri.parse('http://127.0.0.1:8080/v1/projects/anisphere-36cb0/databases/(default)/documents/$path'),
    headers: const {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
    body: jsonEncode({'fields': fields}),
  );
  expect(res.statusCode, 200, reason: 'seeding $path failed: ${res.body}');
}

/// Collapses the profile header all the way, with every tab scrolled to its
/// top: the state in which the pinned app bar and tab bar used to cover the
/// first ~150 points of every tab. The last profile is the one on top: a
/// visitor's profile is pushed over the player's own.
Future<void> collapse(WidgetTester tester) async {
  final state = tester.state<NestedScrollViewState>(find.byType(NestedScrollView).last);
  state.outerController.jumpTo(state.outerController.position.maxScrollExtent);
  for (final p in state.innerController.positions) {
    p.jumpTo(0);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The first row's top must sit at or below the pinned tab bar's bottom.
void expectClear(WidgetTester tester, Finder first, String what) {
  final barBottom = tester.getRect(find.byType(TabBar).last).bottom;
  final top = tester.getRect(first.first).top;
  debugPrint('[overlap] $what: first row top $top, tab bar bottom $barBottom');
  expect(top, greaterThanOrEqualTo(barBottom - 0.5), reason: '$what starts under the pinned bars');
}

/// With the profile header collapsed, the pinned app bar and tab bar must not
/// cover any tab's first row — on a full tab and on an empty one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String me;
  final run = DateTime.now().millisecondsSinceEpoch % 1000000;
  final empty = 'zzempty$run';

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    me = await freshGuest();
    await claimTestHandle('zzlap');
    await FeedService.instance.createPost(content: 'ZZTest overlap post');
    await _seed('ani_videos/zzlap$run', {
      'userId': {'stringValue': me},
      'videoUrl': {'stringValue': 'https://example.invalid/zzlap.mp4'},
      'thumbnailUrl': {'stringValue': ''},
      'caption': {'stringValue': 'ZZTest overlap video'},
      'durationSeconds': {'integerValue': '10'},
      'viewCount': {'integerValue': '12'},
      'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      'isSpoiler': {'booleanValue': false},
    });
    await _seed('users/$empty', {
      'userName': {'stringValue': empty},
      'userNameLower': {'stringValue': empty},
      'displayName': {'stringValue': 'Empty Fan'},
    });
  });

  testWidgets("ui: collapsed, each tab's first row sits below the pinned bars", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile');
    await pumpUntil(tester, find.text('Time Capsule'));

    await collapse(tester);
    await pumpUntil(tester, find.byType(PostCard));
    expectClear(tester, find.byType(PostCard), 'Posts');

    await tester.tap(find.widgetWithText(Tab, 'Ani Videos'));
    await tester.pump(const Duration(milliseconds: 500));
    await collapse(tester);
    final tile = find.ancestor(of: find.text('12'), matching: find.byType(ClipRRect));
    await pumpUntil(tester, tile);
    expectClear(tester, tile, 'Ani Videos');
    expect(tester.takeException(), isNull);
  });

  testWidgets("ui: collapsed, an empty tab's message sits below the pinned bars", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile/$empty');
    await pumpUntil(tester, find.text('Empty Fan'));
    await tester.pump(const Duration(milliseconds: 600)); // the push settles

    await collapse(tester);
    await pumpUntil(tester, find.text('No posts yet.'));
    expectClear(tester, find.text('No posts yet.'), 'empty Posts');

    await tester.tap(find.widgetWithText(Tab, 'Ani Videos'));
    await tester.pump(const Duration(milliseconds: 500));
    await collapse(tester);
    await pumpUntil(tester, find.text('No videos yet.'));
    expectClear(tester, find.text('No videos yet.'), 'empty Ani Videos');
    expect(tester.takeException(), isNull);
  });
}
