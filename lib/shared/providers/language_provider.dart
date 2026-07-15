import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_strings.dart';

class LanguageState {
  final String code;
  final bool isRTL;
  const LanguageState(this.code, this.isRTL);

  TextDirection get direction =>
      isRTL ? TextDirection.rtl : TextDirection.ltr;
}

class LanguageController extends StateNotifier<LanguageState> {
  LanguageController() : super(const LanguageState('en', false)) {
    _load();
  }

  static const _key = 'app_language';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null) setLanguage(code, persist: false);
  }

  Future<void> setLanguage(String code, {bool persist = true}) async {
    final meta = AppStrings.languages.firstWhere(
      (l) => l.code == code,
      orElse: () => AppStrings.languages[1],
    );
    state = LanguageState(meta.code, meta.isRTL);
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, code);
    }
  }
}

final languageProvider =
    StateNotifierProvider<LanguageController, LanguageState>(
        (ref) => LanguageController());

/// Ergonomic translation helper: `ref.tr('feed')`.
extension TrRef on WidgetRef {
  String tr(String key) => AppStrings.t(watch(languageProvider).code, key);
}

extension TrRead on Ref {
  String tr(String key) => AppStrings.t(read(languageProvider).code, key);
}
