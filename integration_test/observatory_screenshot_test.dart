// Screenshot capture for the rebuilt Observatory, in English and Arabic —
// run with `flutter drive` so the driver saves PNGs (see
// test_driver/integration_test.dart).
//
// RUNS AGAINST PRODUCTION ON PURPOSE. The point of these shots is to prove the
// screen renders REAL numbers, so there is no emulator override here — every
// figure captured comes from the live project.
//
// READ-ONLY. This test signs in anonymously (the app's normal guest session)
// but deliberately does NOT call FollowService.ensureProfile, so it creates no
// `users/{uid}` document and does not change the member count it is
// screenshotting. ObservatoryScreen itself only reads.
//
// Captures:
//  1. observatory_en — LTR, English strings.
//  2. observatory_ar — RTL, Arabic strings.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:anisphere/core/constants/app_strings.dart';
import 'package:anisphere/core/theme/app_theme.dart';
import 'package:anisphere/features/observatory/observatory_screen.dart';
import 'package:anisphere/firebase_options.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/shared/providers/language_provider.dart';

/// Real network + Firestore round trips have to land before the shot, and
/// pumpAndSettle would spin forever on any repeating animation.
Future<void> pumpFor(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Mirrors AniSphereApp's wiring (theme, locale delegates, and the
/// provider-driven Directionality that makes Arabic RTL) so the captures match
/// what actually ships.
Widget _app(String langCode) {
  return ProviderScope(
    child: Consumer(
      builder: (context, ref, _) {
        final lang = ref.watch(languageProvider);
        // Drive the locale through the real controller rather than faking it.
        if (lang.code != langCode) {
          Future.microtask(
            () => ref.read(languageProvider.notifier).setLanguage(langCode, persist: false),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          themeMode: ThemeMode.dark,
          locale: Locale(lang.code),
          supportedLocales: AppStrings.languages.map((l) => Locale(l.code)).toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Directionality(
            textDirection: lang.direction,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const ObservatoryScreen(),
        );
      },
    ),
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // No emulator override — production, read-only. See header.
    await AuthService.instance.initAuth();
  });

  testWidgets('capture: Observatory in English', (tester) async {
    await tester.pumpWidget(_app('en'));
    await pumpFor(tester, const Duration(seconds: 8));
    await binding.takeScreenshot('observatory_en');
  });

  testWidgets('capture: Observatory in Arabic (RTL)', (tester) async {
    await tester.pumpWidget(_app('ar'));
    await pumpFor(tester, const Duration(seconds: 8));
    await binding.takeScreenshot('observatory_ar');
  });
}
