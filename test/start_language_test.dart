import 'dart:ui';

import 'package:anisphere/shared/providers/language_provider.dart';
import 'package:flutter/foundation.dart';
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

  group('on iOS the pick is the app\'s AppleLanguages', () {
    final written = <String>[];
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      written.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LanguageController.iosLanguage, (call) async {
        if (call.method == 'set') written.add(call.arguments as String);
        return null;
      });
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(LanguageController.iosLanguage, null);
    });

    test('a pick writes AppleLanguages, not the app\'s own preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = LanguageController(initial: start(const [Locale('en')]));
      await controller.setLanguage('fr');
      expect(controller.state.code, 'fr', reason: 'applies at once');
      expect(written, ['fr']);
      expect(prefs.getString(LanguageController.prefsKey), isNull);
      controller.dispose();
    });

    test('a pick saved before the change is moved into AppleLanguages once, and opens this launch', () async {
      SharedPreferences.setMockInitialValues({LanguageController.prefsKey: 'tr'});
      final prefs = await SharedPreferences.getInstance();
      final first = await LanguageController.launchLanguage(prefs, const [Locale('en')]);
      expect(first.code, 'tr');
      expect(written, ['tr']);
      expect(prefs.getString(LanguageController.prefsKey), isNull);
      // The next launch: iOS now puts the app's setting first in the phone's list.
      final next = await LanguageController.launchLanguage(prefs, const [Locale('tr'), Locale('en')]);
      expect(next.code, 'tr');
      expect(written, ['tr'], reason: 'migrated once');
    });

    test('an old pick the app no longer offers is dropped, not written', () async {
      SharedPreferences.setMockInitialValues({LanguageController.prefsKey: 'xx'});
      final prefs = await SharedPreferences.getInstance();
      final state = await LanguageController.launchLanguage(prefs, const [Locale('ko')]);
      expect(state.code, 'ko');
      expect(written, isEmpty);
      expect(prefs.getString(LanguageController.prefsKey), isNull);
    });
  });

  test('elsewhere the saved pick stays in the app\'s preferences and outranks the phone', () async {
    SharedPreferences.setMockInitialValues({LanguageController.prefsKey: 'en'});
    final prefs = await SharedPreferences.getInstance();
    final state = await LanguageController.launchLanguage(prefs, const [Locale('ar')]);
    expect(state.code, 'en');
    expect(prefs.getString(LanguageController.prefsKey), 'en');
  });
}
