import 'dart:ui';

import 'package:anisphere/shared/providers/language_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The language the app opens in: the player's saved pick, else the first of
/// the phone's preferred languages the app has, else English.
void main() {
  LanguageState start(List<Locale> phone, {String? saved}) =>
      LanguageController.startLanguage(saved: saved, phone: phone);

  test('a phone set to German then Arabic opens in Arabic, right to left', () {
    final s = start(const [Locale('de', 'DE'), Locale('ar', 'SA')]);
    expect(s.code, 'ar');
    expect(s.isRTL, isTrue);
  });

  test('a saved English pick beats an Arabic phone', () {
    final s = start(const [Locale('ar', 'SA')], saved: 'en');
    expect(s.code, 'en');
    expect(s.isRTL, isFalse);
  });

  test('a phone with none of the eight opens in English', () {
    expect(start(const [Locale('de', 'DE'), Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')]).code, 'en');
    expect(start(const []).code, 'en');
  });

  test('region and script do not matter, only the language', () {
    expect(start(const [Locale('fr', 'CA')]).code, 'fr');
    expect(start(const [Locale.fromSubtags(languageCode: 'ja', countryCode: 'JP')]).code, 'ja');
  });

  test('a saved pick the app does not offer is passed over', () {
    expect(start(const [Locale('ko', 'KR')], saved: 'xx').code, 'ko');
  });

  test('only an explicit pick is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = LanguageController(initial: start(const [Locale('ar')]));
    expect(controller.state.code, 'ar');
    expect(prefs.getString(LanguageController.prefsKey), isNull, reason: "the phone's language is not saved");
    await controller.setLanguage('fr');
    expect(prefs.getString(LanguageController.prefsKey), 'fr');
    await controller.setLanguage('es', persist: false);
    expect(prefs.getString(LanguageController.prefsKey), 'fr');
    controller.dispose();
  });
}
