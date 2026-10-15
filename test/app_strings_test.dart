import 'package:anisphere/core/constants/app_strings.dart';
import 'package:anisphere/data/models/ani_video.dart';
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
    for (final MapEntry(key: lang, value: strings) in AppStrings.values.entries) {
      for (final key in const ['maxVideoDuration', 'videoTooLong']) {
        final text = strings[key];
        if (text == null || !(text.contains(western) || text.contains(arabicIndic))) {
          stale.add('$lang.$key: $text');
        }
      }
    }
    expect(stale, isEmpty);
  });
}
