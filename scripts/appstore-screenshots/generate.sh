#!/usr/bin/env bash
# Composes the App Store screenshots from the raw captures in out/raw (see capture.sh) into
# fastlane/screenshots/<locale>/, ready for `fastlane upload_screenshots`.
#
# Usage: scripts/appstore-screenshots/generate.sh [locale ...]   (defaults to every locale in locales.sh)
#
# The widgets screenshot needs a home screen with Dime's widgets, which capture.sh can't set up, so those
# captures are kept in widgets/<locale>.png (1320x2868); locales without one get no widgets screenshot.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
source "$DIR/locales.sh"

LOCALES=("$@")
[ ${#LOCALES[@]} -gt 0 ] || LOCALES=("${ALL_LOCALES[@]}")

mkdir -p "$DIR/out"
swiftc -O "$DIR/compose.swift" -o "$DIR/out/compose"

for locale in "${LOCALES[@]}"; do
  out="$REPO/fastlane/screenshots/$locale"
  rm -rf "$out"
  if [ -f "$DIR/widgets/$locale.png" ]; then
    cp "$DIR/widgets/$locale.png" "$DIR/out/raw/$locale/iphone/widgets.png"
  fi
  "$DIR/out/compose" "$locale" "$DIR/out/raw/$locale" "$out" "$DIR/captions.json" > /dev/null
  echo "$locale: $(find "$out" -name '*.png' | wc -l | tr -d ' ') screenshots"
done

# Storefronts that share another locale's screenshots.
for pair in es-MX:es-ES fr-CA:fr-FR; do
  target="${pair%%:*}" source="${pair##*:}"
  if [ -d "$REPO/fastlane/screenshots/$source" ]; then
    rm -rf "$REPO/fastlane/screenshots/$target"
    cp -R "$REPO/fastlane/screenshots/$source" "$REPO/fastlane/screenshots/$target"
  fi
done
