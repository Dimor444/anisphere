import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anisphere/data/sample_data.dart';
import 'package:anisphere/data/models/user_model.dart';
import 'package:anisphere/core/constants/app_languages.dart';
import 'package:anisphere/l10n/app_localizations.dart';
import 'package:anisphere/shared/providers/language_provider.dart';
import 'package:anisphere/core/utils/formatters.dart';
import 'package:anisphere/shared/widgets/verified_badge.dart';
import 'package:anisphere/shared/widgets/ani_gold_icon.dart';
import 'package:anisphere/shared/widgets/ani_gem_icon.dart';

void main() {
  group('Brand widgets render (network-free)', () {
    testWidgets('VerifiedBadge paints', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: VerifiedBadge(size: BadgeSize.lg),
      ));
      expect(find.byType(VerifiedBadge), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('AniGold shows infinity glyph', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: AniGoldIcon(size: BadgeSize.lg),
      ));
      expect(find.text('∞'), findsOneWidget);
    });

    testWidgets('AniGem paints', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: AniGemIcon(size: BadgeSize.lg),
      ));
      expect(find.byType(AniGemIcon), findsOneWidget);
    });
  });

  group('Data integrity', () {
    test('main user matches spec', () {
      const u = SampleData.mainUser;
      expect(u.username, 'KazeNoYuki');
      expect(u.level, UserLevel.otakuElite);
      expect(u.isVerified, isTrue);
      // No isPlusUser check: Plus is not a fact about the sample user. Since
      // fcaaf45 it comes from users/{uid}.isPlus, which only the server writes
      // (isPlusProvider), and nothing reads this flag any more.
      expect(u.watchedAnime, 347);
      expect(u.followers, 2341);
      expect(u.streak, 42);
      expect(u.aniGold, 1240);
      expect(u.aniGem, 85);
    });

    test('exactly 30 anime in catalogue', () {
      expect(SampleData.animeList.length, 30);
    });

    test('5 sample posts incl. a spoiler', () {
      final posts = SampleData.posts;
      expect(posts.length, 5);
      expect(posts.any((p) => p.isSpoiler), isTrue);
    });

    test('all AniPlus discount codes present', () {
      for (final code in ['ANISPHERE', 'WEEBGOD', 'WELCOME14', 'ANIMASTER']) {
        expect(SampleData.plusDiscountCodes.containsKey(code), isTrue, reason: code);
      }
    });

    test('8 languages incl. RTL Arabic', () {
      expect(AppLanguages.all.length, 8);
      expect(AppLanguages.all.firstWhere((l) => l.code == 'ar').isRTL, isTrue);
    });
  });

  group('Formatters', () {
    test('thousands', () => expect(Fmt.thousands(1240), '1,240'));
    test('compact K', () => expect(Fmt.compact(18400), '18.4K'));
    test('compact M', () => expect(Fmt.compact(1200000), '1.2M'));
    test('country flag from an ISO code, nothing for the unknown marker', () {
      expect(Fmt.countryFlag('TR'), '🇹🇷');
      expect(Fmt.countryFlag('jp'), '🇯🇵');
      expect(Fmt.countryFlag('XX'), '');
      expect(Fmt.countryFlag(''), '');
      expect(Fmt.countryFlag('U1'), '');
    });
    test('translation falls back to English', () async {
      expect(lookupAppLocalizations(const Locale('ja')).feed, 'フィード');
      // A message a language lacks reads in English (bio is one of the gaps).
      expect(lookupAppLocalizations(const Locale('ar')).bio, 'Bio');
      // An unknown language is English: the controller never asks for it.
      SharedPreferences.setMockInitialValues({});
      final controller = LanguageController();
      await controller.setLanguage('xx', persist: false);
      expect(controller.state.code, 'en');
      controller.dispose();
    });
  });
}
