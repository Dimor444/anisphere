import 'dart:convert';
import 'dart:io';

import 'package:anisphere/core/constants/app_languages.dart';
import 'package:anisphere/data/models/ani_video.dart';
import 'package:anisphere/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The limit went from 60 to 120 seconds in September and every language
  // kept saying 60. The text has no placeholders, so the number is written
  // into each translation; this is what keeps it in step with the constant.
  test('the video length limit matches AniVideoData.maxDurationSeconds in every language', () {
    const western = '${AniVideoData.maxDurationSeconds}';
    // Arabic writes the number in Arabic-Indic digits.
    final arabicIndic = western.split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[int.parse(d)]).join();
    final stale = <String>[];
    for (final lang in AppLanguages.all) {
      final l = lookupAppLocalizations(Locale(lang.code));
      for (final (key, text) in [('maxVideoDuration', l.maxVideoDuration), ('videoTooLong', l.videoTooLong)]) {
        if (!(text.contains(western) || text.contains(arabicIndic))) {
          stale.add('${lang.code}.$key: $text');
        }
      }
    }
    expect(stale, isEmpty);
  });

  // The onboarding slides are the first thing anyone sees, and they once
  // promised a League and AniMatch the app does not show. Every language
  // carries every slide. Read from the ARB files: the generated class shows
  // English for a message a language lacks, so it cannot tell one missing.
  test('every language has all six onboarding slide strings', () {
    const keys = ['onbTitle1', 'onbBody1', 'onbTitle2', 'onbBody2', 'onbTitle3', 'onbBody3'];
    final missing = <String>[
      for (final lang in AppLanguages.all)
        for (final k in keys)
          if (((jsonDecode(File('lib/l10n/app_${lang.code}.arb').readAsStringSync())
                          as Map<String, dynamic>)[k] as String? ??
                      '')
                  .trim()
                  .isEmpty)
            '${lang.code}.$k',
    ];
    expect(missing, isEmpty);
  });
}
