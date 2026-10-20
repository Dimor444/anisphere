import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/features/profile/profile_screen.dart';
import 'package:anisphere/features/profile/time_capsule_screen.dart';
import 'package:anisphere/features/profile/wrapped_screen.dart';
import 'package:anisphere/firebase_options.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Writes a document with the emulator's owner credential, past the rules.
Future<void> _seed(String path, Map<String, Map<String, dynamic>> fields) async {
  final res = await http.patch(
    Uri.parse('http://127.0.0.1:8080/v1/projects/anisphere-36cb0/databases/(default)/documents/$path'),
    headers: const {'Authorization': 'Bearer owner', 'Content-Type': 'application/json'},
    body: jsonEncode({'fields': fields}),
  );
  expect(res.statusCode, 200, reason: 'seeding $path failed: ${res.body}');
}

Future<void> _seedVideo(String id, String userId, {bool spoiler = false, String thumbnail = ''}) => _seed('ani_videos/$id', {
      'userId': {'stringValue': userId},
      'userName': {'stringValue': ''},
      'userAvatar': {'stringValue': ''},
      'isVerified': {'booleanValue': false},
      'videoUrl': {'stringValue': 'https://example.invalid/$id.mp4'},
      'thumbnailUrl': {'stringValue': thumbnail},
      'caption': {'stringValue': 'ZZTest profile video'},
      'hashtags': {'arrayValue': <String, dynamic>{}},
      'durationSeconds': {'integerValue': '10'},
      'likes': {'integerValue': '0'},
      'commentsCount': {'integerValue': '0'},
      'shareCount': {'integerValue': '0'},
      'viewCount': {'integerValue': '12'},
      'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
      'isSpoiler': {'booleanValue': spoiler},
    });

/// Every profile has one set of tabs, built from what is real — Posts and
/// Ani Videos — plus Stats on the player's own while kAniStatsEnabled is on;
/// Wrapped's banner shows only while kWrappedEnabled is on, and the Time
/// Capsule button only while kTimeCapsuleEnabled is. Tabs are counted
/// off screen too, and any build error fails the test: a tab count that
/// disagreed with the bar is what broke this profile before.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String me;
  final other = 'zzvisit${DateTime.now().millisecondsSinceEpoch % 1000000}';
  final run = DateTime.now().millisecondsSinceEpoch % 1000000;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    me = await freshGuest();
    await claimTestHandle('zzprof');
    await _seed('users/$other', {
      'userName': {'stringValue': other},
      'userNameLower': {'stringValue': other},
      'displayName': {'stringValue': 'Visited Fan'},
      'countryCode': {'stringValue': 'JP'},
    });
    await _seedVideo('zzmine$run', me);
    await _seedVideo('zztheirs$run', other,
        thumbnail: 'https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/bx154587-qQTzQnEJJ3oB.jpg');
    await _seedVideo('zzspoil$run', other, spoiler: true);
  });

  List<String?> tabLabels(WidgetTester tester) =>
      tester.widgetList<Tab>(find.byType(Tab, skipOffstage: false)).map((t) => t.text).toList();

  Future<void> openTabs(WidgetTester tester) async {
    await tester.dragUntilVisible(
        find.widgetWithText(Tab, 'Posts'), find.byType(NestedScrollView), const Offset(0, -200));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets("ui: the player's own profile has the real tabs only", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile');
    // The Anime DNA heading is built with the banners, in the same column.
    await pumpUntil(tester, find.text('🧬 Anime DNA'));
    expect(find.textContaining('Wrapped', skipOffstage: false), kWrappedEnabled ? findsWidgets : findsNothing);
    expect(find.text('Time Capsule', skipOffstage: false), kTimeCapsuleEnabled ? findsOneWidget : findsNothing);

    await openTabs(tester);
    expect(tabLabels(tester), ['Posts', 'Ani Videos', if (kAniStatsEnabled) 'Stats']);

    await tester.tap(find.widgetWithText(Tab, 'Ani Videos'));
    await pumpUntil(tester, find.byIcon(LucideIcons.play));
    expect(find.byIcon(LucideIcons.play), findsOneWidget); // the one seeded video of mine
    expect(tester.takeException(), isNull);
  });

  testWidgets("ui: a visitor sees the same tabs, and the player's videos", (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile/$other');
    await pumpUntil(tester, find.text('Visited Fan'));
    // The visitor's page fades in over the player's own; until the fade ends
    // both are mounted, and openTabs needs the one scroll view.
    await tester.pump(const Duration(milliseconds: 600)); // the push settles

    await openTabs(tester);
    expect(tabLabels(tester), ['Posts', 'Ani Videos']);

    await tester.tap(find.widgetWithText(Tab, 'Ani Videos'));
    await pumpUntil(tester, find.byIcon(LucideIcons.play));
    expect(find.byIcon(LucideIcons.play), findsNWidgets(2));
    // The spoiler shows no picture.
    expect(find.byIcon(LucideIcons.eyeOff), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
