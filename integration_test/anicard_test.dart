import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/features/profile/widgets/ani_card.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/my_list_service.dart';
import 'package:anisphere/shared/widgets/gradient_button.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// The profile's AniCard, end to end on the emulator: the player's own
/// handle and their My List's completed count, nothing of the sample user.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String handle;

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    handle = await claimTestHandle('zzcard');
  });

  testWidgets("ui: the AniCard is the player's own", (tester) async {
    // Two completed, one planned — only the completed count.
    final list = MyListService.instance;
    await list.addToMyList(154587, 'Frieren', '', ListStatus.completed);
    await list.addToMyList(20, 'Naruto', '', ListStatus.completed);
    await list.addToMyList(16498, 'Attack on Titan', '', ListStatus.planning);

    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();
    appRouter.go('/profile');
    await pumpUntil(tester, find.byIcon(LucideIcons.share2));
    await tester.tap(find.byIcon(LucideIcons.share2).first);

    final card = find.byType(AniCard);
    await pumpUntil(tester, find.descendant(of: card, matching: find.text('Completed')));
    await pumpUntil(tester, find.descendant(of: card, matching: find.text('2')));
    expect(find.descendant(of: card, matching: find.text('@$handle')), findsOneWidget);
    for (final gone in ['KazeNoYuki', '347', '4.8K', '1203h', '#847']) {
      expect(find.descendant(of: card, matching: find.textContaining(gone)), findsNothing, reason: gone);
    }

    // Share opens once the card shows the player and the count has settled.
    final share = find.widgetWithText(GradientButton, 'Share AniCard');
    expect(tester.widget<GradientButton>(share).onPressed, isNotNull);
  });
}
