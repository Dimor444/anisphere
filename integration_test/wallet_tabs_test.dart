import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:anisphere/app.dart';
import 'package:anisphere/features/achievements/achievements_screen.dart';
import 'package:anisphere/features/fm_radio/fm_radio_screen.dart';
import 'package:anisphere/core/constants/purchases.dart';
import 'package:anisphere/core/router/app_router.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/shared/widgets/ani_gem_icon.dart';

import 'support/session.dart';

Future<void> pumpUntil(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

List<String?> tabLabels(WidgetTester tester) =>
    tester.widgetList<Tab>(find.byType(Tab, skipOffstage: false)).map((t) => t.text).toList();

/// The wallet sells only what can be bought: Recharge and AniPlus follow
/// kAniGemsEnabled and kAniPlusForSale, the gem shows only with gems, a link
/// to a hidden tab lands on the first one, and the drawer offers no upgrade
/// to a plan that cannot be bought — nor Achievements or FM Radio, which
/// follow kAchievementsEnabled and kFmRadioEnabled.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
    await freshGuest();
    await claimTestHandle('zzwallet');
  });

  testWidgets('ui: the wallet sells only what can be bought', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AniSphereApp()));
    await tester.pump();

    appRouter.go('/wallet');
    await pumpUntil(tester, find.widgetWithText(Tab, 'Earn'));
    expect(tabLabels(tester), [
      'Earn',
      'Spend',
      if (kAniGemsEnabled) 'Recharge',
      if (kAniPlusForSale) '💎 AniPlus',
      'My Items',
    ]);
    if (!kAniGemsEnabled) expect(find.byType(AniGemIcon, skipOffstage: false), findsNothing);
    expect(find.textContaining('Demo — no real purchase', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);

    // A link to a hidden tab opens the wallet on its first tab.
    appRouter.go('/wallet?tab=${kAniPlusForSale ? 'earn' : 'plus'}');
    await pumpUntil(tester, find.widgetWithText(Tab, 'Earn'));
    expect(tester.takeException(), isNull);

    // The drawer: no gem, and no upgrade to a plan nobody can buy.
    appRouter.go('/feed');
    await pumpUntil(tester, find.byIcon(LucideIcons.menu));
    await tester.tap(find.byIcon(LucideIcons.menu).first);
    await pumpUntil(tester, find.byType(Drawer));
    await tester.pump(const Duration(milliseconds: 400));
    if (!kAniPlusForSale) expect(find.textContaining('Upgrade to AniPlus'), findsNothing);
    if (!kAniGemsEnabled) expect(find.byType(AniGemIcon, skipOffstage: false), findsNothing);
    // Achievements, between Seasonal and Wallet. Its neighbours are checked
    // first, so its absence is not just a row the list had not built.
    Finder inDrawer(String label) =>
        find.descendant(of: find.byType(Drawer), matching: find.text(label), skipOffstage: false);
    expect(inDrawer('Seasonal'), findsOneWidget);
    expect(inDrawer('Wallet'), findsOneWidget);
    expect(inDrawer('Achievements'), kAchievementsEnabled ? findsOneWidget : findsNothing);
    // FM Radio, between Observatory and Settings, checked the same way.
    expect(inDrawer('Observatory'), findsOneWidget);
    expect(inDrawer('Settings'), findsOneWidget);
    expect(inDrawer('FM Radio'), kFmRadioEnabled ? findsOneWidget : findsNothing);
    expect(tester.takeException(), isNull);
  });
}
