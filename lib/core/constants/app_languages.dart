/// The languages the app offers, in the order its pickers list them. Each
/// one's strings are in lib/l10n/app_<code>.arb.
class AppLanguages {
  AppLanguages._();

  static const List<LangMeta> all = [
    LangMeta('ar', 'العربية', '🇸🇦', isRTL: true),
    LangMeta('en', 'English', '🇺🇸'),
    LangMeta('ja', '日本語', '🇯🇵'),
    LangMeta('ko', '한국어', '🇰🇷'),
    LangMeta('es', 'Español', '🇪🇸'),
    LangMeta('fr', 'Français', '🇫🇷'),
    LangMeta('tr', 'Türkçe', '🇹🇷'),
    LangMeta('id', 'Indonesia', '🇮🇩'),
  ];
}

class LangMeta {
  final String code;
  final String name;
  final String flag;
  final bool isRTL;
  const LangMeta(this.code, this.name, this.flag, {this.isRTL = false});
}
