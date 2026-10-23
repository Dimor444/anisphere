import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Where the player's own pick is kept — everywhere but iOS, and on iOS
  /// before the pick moved to the app's AppleLanguages (see [launchLanguage]).
  static const prefsKey = 'app_language';

  /// On iOS a pick is the app's own AppleLanguages, the value Settings ›
  /// AniSphere › Language reads and writes, so the picker and Settings are
  /// one setting: whichever was used last holds it, and each shows what the
  /// other chose. iOS puts it first in the phone's languages from the next
  /// launch on.
  static const iosLanguage = MethodChannel('anisphere/app_language');

  static bool get _onIos => defaultTargetPlatform == TargetPlatform.iOS;

  /// The language this launch opens in, read before the first frame. On iOS
  /// the phone's languages already carry the app's setting; a pick saved
  /// before it moved there is written into it once, and opens this launch,
  /// since the phone's list was read before the write.
  static Future<LanguageState> launchLanguage(SharedPreferences prefs, List<Locale> phone) async {
    final saved = prefs.getString(prefsKey);
    if (!_onIos || saved == null) return startLanguage(saved: _onIos ? null : saved, phone: phone);
    final kept = AppLanguages.all.any((l) => l.code == saved);
    if (kept) await iosLanguage.invokeMethod<void>('set', saved);
    await prefs.remove(prefsKey);
    return startLanguage(saved: kept ? saved : null, phone: phone);
  }

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

  /// Switches the language, at once. [persist] keeps it as the player's
  /// pick — on iOS in the app's AppleLanguages, elsewhere in the app's
  /// preferences, where it outranks the phone on every launch. Only a choice
  /// made in a language picker passes it; the phone's language is never
  /// saved.
  Future<void> setLanguage(String code, {bool persist = true}) async {
    final meta = AppLanguages.all.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguages.all[1],
    );
    state = LanguageState(meta.code, meta.isRTL);
    if (!persist) return;
    if (_onIos) {
      await iosLanguage.invokeMethod<void>('set', meta.code);
    } else {
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
