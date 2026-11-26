#!/usr/bin/env bash
# Captures the raw app screens for the App Store screenshots, per App Store locale, on an
# iPhone 17 Pro Max (iOS 26.4) and an iPhone Duo (iOS 27.1) simulator. Runs a Debug build
# against the seeded `-demoData varied` store, in the locale's language, region and currency.
#
# Usage: scripts/appstore-screenshots/capture.sh [--skip-build] [--only iphone|duo] [locale ...]
# Writes out/raw/<locale>/{iphone,duo}/<screen>.png. Defaults to every locale in locales.sh.
#
# Uses two dedicated simulators, "Dime Screenshots iPhone" and "Dime Screenshots Duo", created
# on first run: demo runs write the chosen currency to the app's settings.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
source "$DIR/locales.sh"

BUNDLE_ID="com.rafaelsoh.dime"
DERIVED="$DIR/out/derived"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.1.app/Contents/Developer}"

BUILD=1
ONLY=""
LOCALES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) BUILD=0 ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) LOCALES+=("$1") ;;
  esac
  shift
done
[ ${#LOCALES[@]} -gt 0 ] || LOCALES=("${ALL_LOCALES[@]}")

# name|appearance|launch arguments
IPHONE_SCREENS=(
  "log|light|"
  "insights|light|-screenshotTab Insights -insightsTimeFrame 1 -insightsOffset -1"
  "add|light|-screenshotAdd"
  "budgets|light|-screenshotTab Budget"
  "settings|light|-screenshotTab Settings"
  "dark_log|dark|"
  "categories|light|-screenshotTab Insights -insightsTimeFrame 2 -insightsSheet categories"
)
DUO_SCREENS=(
  "add|light|-screenshotAdd"
  "insights|light|-screenshotTab Insights -insightsTimeFrame 1 -insightsOffset -1"
  "budgets|light|-screenshotTab Budget"
  "settings|light|-screenshotTab Settings"
  "dark_log|dark|"
  "categories|light|-screenshotTab Insights -insightsTimeFrame 2 -insightsSheet categories"
)

simulator() {
  local name="$1" type="$2" runtime="$3" udid
  udid="$(xcrun simctl list devices -j | python3 -c "
import json, sys
for devices in json.load(sys.stdin)['devices'].values():
    for d in devices:
        if d['name'] == '$name' and d['isAvailable']:
            print(d['udid']); sys.exit()")"
  [ -n "$udid" ] || udid="$(xcrun simctl create "$name" "com.apple.CoreSimulator.SimDeviceType.$type" "com.apple.CoreSimulator.SimRuntime.$runtime")"
  printf '%s' "$udid"
}

width_of() {
  sips -g pixelWidth "$1" 2>/dev/null | awk '/pixelWidth/ {print $2}'
}

# Screenshots the display of the expected width. The Duo defaults to its folded (black) inner
# display; its cover screen is display 1.
snap() {
  local udid="$1" out="$2" width="$3"
  xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1 || true
  [ "$(width_of "$out")" = "$width" ] && return
  xcrun simctl io "$udid" screenshot --display=1 "$out" >/dev/null 2>&1 || true
  [ "$(width_of "$out")" = "$width" ] && return
  echo "No ${width}px-wide display on $udid" >&2
  return 1
}

prepare() {
  local udid="$1"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$APP"
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState discharging --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 --dataNetwork wifi
  # The first launch shows onboarding.
  xcrun simctl launch "$udid" "$BUNDLE_ID" -demoData varied >/dev/null
  sleep 8
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
}

capture() {
  local udid="$1" device="$2" width="$3" locale="$4"
  shift 4
  local language region currency entry name appearance args out
  read -r language region currency <<< "$(locale_settings "$locale")"
  out="$DIR/out/raw/$locale/$device"
  mkdir -p "$out"
  for entry in "$@"; do
    IFS='|' read -r name appearance args <<< "$entry"
    xcrun simctl ui "$udid" appearance "$appearance"
    # shellcheck disable=SC2086
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" \
      -AppleLanguages "($language)" -AppleLocale "$region" -demoData varied -demoCurrency "$currency" $args >/dev/null
    sleep 7
    snap "$udid" "$out/$name.png" "$width"
    echo "  $locale $device $name"
  done
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl ui "$udid" appearance light
}

if [ "$BUILD" = 1 ]; then
  echo "==> Building Debug for the simulator"
  xcodebuild -project "$REPO/app/dime.xcodeproj" -scheme dime -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" build -quiet
fi
APP="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' | head -1)"
[ -d "$APP" ] || { echo "No build in $DERIVED; run without --skip-build" >&2; exit 1; }

if [ "$ONLY" != duo ]; then
  IPHONE="$(simulator "Dime Screenshots iPhone" iPhone-17-Pro-Max iOS-26-4)"
  echo "==> iPhone 17 Pro Max ($IPHONE)"
  prepare "$IPHONE"
  for locale in "${LOCALES[@]}"; do
    capture "$IPHONE" iphone 1320 "$locale" "${IPHONE_SCREENS[@]}"
  done
fi

if [ "$ONLY" != iphone ]; then
  DUO="$(simulator "Dime Screenshots Duo" iPhone-Duo iOS-27-1)"
  echo "==> iPhone Duo ($DUO)"
  prepare "$DUO"
  for locale in "${LOCALES[@]}"; do
    capture "$DUO" duo 1398 "$locale" "${DUO_SCREENS[@]}"
  done
fi
