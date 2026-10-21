import 'package:anisphere/core/constants/app_languages.dart';
import 'package:anisphere/data/models/news.dart';
import 'package:anisphere/features/ani_videos/upload_video_screen.dart';
import 'package:anisphere/features/my_list/widgets/list_status_ui.dart';
import 'package:anisphere/features/news/news_screen.dart';
import 'package:anisphere/features/seasonal/seasonal_screen.dart';
import 'package:anisphere/features/settings/delete_account_screen.dart';
import 'package:anisphere/l10n/app_localizations.dart';
import 'package:anisphere/services/auth_service.dart';
import 'package:anisphere/services/my_list_service.dart';
import 'package:anisphere/shared/providers/language_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The labels chosen from a value rather than named outright, where the
/// screens that show them cannot be opened in a test: the upload failure,
/// the deletion failure, and Seasonal's weekdays, which need AniList's
/// schedule. Each must name its own message in every language.
void main() {
  final all = [for (final lang in AppLanguages.all) (lang.code, lookupAppLocalizations(Locale(lang.code)))];

  test('the upload-failure dialog acknowledges a cap and cancels anything else', () {
    for (final (code, l) in all) {
      expect(uploadFailureDismissLabel(l, capped: true), l.ok, reason: code);
      expect(uploadFailureDismissLabel(l, capped: false), l.cancel, reason: code);
    }
  });

  test('each way deletion can fail has its own message', () {
    for (final (code, l) in all) {
      expect(deletionFailureMessage(l, AccountDeletionFailure.unreachable), l.deleteFailedUnreachable, reason: code);
      expect(deletionFailureMessage(l, AccountDeletionFailure.refused), l.deleteFailedNothingChanged, reason: code);
      expect(deletionFailureMessage(l, AccountDeletionFailure.unconfirmed), l.deleteFailedUnsure, reason: code);
    }
  });

  test('a stored status or category the app does not know reads as Planning or News', () {
    for (final (code, l) in all) {
      expect(ListStatus.fromValue('REPEATING').label(l), l.planning, reason: code);
      expect(NewsCategory.fromValue('Gossip').label(l), l.news, reason: code);
    }
  });

  testWidgets('weekday names in every language; a weekday outside 1–7 throws', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var labels = <String>[];
    Object? outside;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (_, ref, __) {
        labels = [for (var d = DateTime.monday; d <= DateTime.sunday; d++) SeasonalScreen.dayLabel(ref, d)];
        try {
          SeasonalScreen.dayLabel(ref, 8);
        } catch (e) {
          outside = e;
        }
        return const SizedBox();
      }),
    ));
    for (final (code, l) in all) {
      await container.read(languageProvider.notifier).setLanguage(code, persist: false);
      await tester.pump();
      expect(labels, [l.dayMon, l.dayTue, l.dayWed, l.dayThu, l.dayFri, l.daySat, l.daySun], reason: code);
      expect(outside, isA<RangeError>(), reason: code);
    }
  });
}
