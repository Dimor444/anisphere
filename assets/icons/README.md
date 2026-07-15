# App icons & splash

To generate launcher icons and the native splash screen, drop these PNGs here, then
run the generators (see project README):

| File | Size | Used by |
|------|------|---------|
| `app_icon.png` | 1024×1024 | `flutter_launcher_icons` (iOS + Android legacy) |
| `app_icon_foreground.png` | 1024×1024, transparent, logo centred at ~66% | Android adaptive foreground |
| `splash_logo.png` | ~512×512, transparent | `flutter_native_splash` |

Brand mark: a circle with the infinity (`∞`) symbol on the `#0D0F1A` navy background,
purple→pink→cyan gradient ring. The in-app `AniLogo` widget renders the same mark in code.

These are optional — the app ships with an animated in-app splash and runs fine without them.
