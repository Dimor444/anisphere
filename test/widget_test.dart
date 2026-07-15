import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anisphere/data/sample_data.dart';
import 'package:anisphere/data/models/user_model.dart';
import 'package:anisphere/core/constants/app_strings.dart';
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
      expect(u.isPlusUser, isTrue);
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
      expect(AppStrings.languages.length, 8);
      expect(AppStrings.languages.firstWhere((l) => l.code == 'ar').isRTL, isTrue);
    });
  });

  group('Formatters', () {
    test('thousands', () => expect(Fmt.thousands(1240), '1,240'));
    test('compact K', () => expect(Fmt.compact(18400), '18.4K'));
    test('compact M', () => expect(Fmt.compact(1200000), '1.2M'));
    test('translation falls back to English', () {
      expect(AppStrings.t('ja', 'feed'), 'フィード');
      expect(AppStrings.t('xx', 'feed'), 'Feed'); // unknown lang → en
    });
  });
}
