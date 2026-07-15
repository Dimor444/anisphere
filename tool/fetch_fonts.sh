#!/usr/bin/env bash
# Re-fetch the vendored variable fonts into assets/fonts/.
# The repo already ships these TTFs; run this only if they go missing.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/fonts

echo "↓ Outfit"
curl -fsSL "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit%5Bwght%5D.ttf" \
  -o assets/fonts/Outfit.ttf

echo "↓ Space Grotesk"
curl -fsSL "https://github.com/google/fonts/raw/main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf" \
  -o assets/fonts/SpaceGrotesk.ttf

echo "✓ Fonts in assets/fonts/ — run 'flutter pub get' if you changed pubspec."
