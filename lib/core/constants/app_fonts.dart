/// Bundled font family names. The actual variable TTFs live in `assets/fonts/`
/// and are registered in `pubspec.yaml`, so the app needs **no network** for
/// typography (unlike runtime google_fonts fetching).
class AppFonts {
  AppFonts._();

  /// UI text — Outfit (variable, weights 100–900).
  static const String outfit = 'Outfit';

  /// Numbers / stats — Space Grotesk (variable, weights 300–700).
  static const String spaceGrotesk = 'SpaceGrotesk';
}
