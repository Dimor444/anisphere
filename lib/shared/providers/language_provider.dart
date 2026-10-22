import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_languages.dart';
import '../../l10n/app_localizations.dart';

class LanguageState {
  final String code;
  final bool isRTL;
  const LanguageState(this.code, this.isRTL);

  TextDirection get direction =>
      isRTL ? TextDirection.rtl : TextDirection.ltr;
}

class LanguageController extends StateNotifier<LanguageState> {
  /// [initial] is the language main() worked out before the first frame, from
  /// [startLanguage]. Without it — tests, a bare ProviderScope — the
  /// controller starts from the phone's languages and applies a saved pick
  /// once it has been read.
  LanguageController({LanguageState? initial})
      : super(initial ?? startLanguage(saved: null, phone: PlatformDispatcher.instance.locales)) {
    if (initial == null) _load();
  }

  /// Where the player's own pick is kept.
  static const prefsKey = 'app_language';

  /// The language the app opens in: the player's saved pick; else the first
  /// of the phone's preferred languages the app has, by language alone
  /// (fr-CA is French); else English.
  static LanguageState startLanguage({required String? saved, required List<Locale> phone}) {
    LangMeta? offered(String? code) {
      for (final l in AppLanguages.all) {
        if (l.code == code) return l;
      }
      return null;
    }

    final meta = offered(saved) ??
        phone.map((l) => offered(l.languageCode)).nonNulls.firstOrNull ??
        offered('en')!;
    return LanguageState(meta.code, meta.isRTL);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(prefsKey);
    if (code != null) setLanguage(code, persist: false);
  }

  /// Switches the language. [persist] saves it as the player's pick, which
  /// then outranks the phone on every launch — only a choice made in a
  /// language picker passes it; the phone's language is never saved.
  Future<void> setLanguage(String code, {bool persist = true}) async {
    final meta = AppLanguages.all.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguages.all[1],
    );
    state = LanguageState(meta.code, meta.isRTL);
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, code);
    }
  }
}

final languageProvider =
    StateNotifierProvider<LanguageController, LanguageState>(
        (ref) => LanguageController());

/// The chosen language's generated strings: `ref.l10n.feed`. Watches the
/// language, so switching it rebuilds the caller.
extension L10nRef on WidgetRef {
  AppLocalizations get l10n => lookupAppLocalizations(Locale(watch(languageProvider).code));
}
