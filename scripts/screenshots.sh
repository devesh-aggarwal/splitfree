#!/usr/bin/env bash
#
# App Store screenshots, on the two device sizes Apple requires.
#
# Each shot is a fresh launch with arguments that put the app on the screen we
# want. No taps and no coordinates, so a layout change cannot silently start
# photographing the wrong thing. The seeded ledger comes from DemoData.swift,
# which exists only in debug builds.
#
# Output is gitignored. Screenshots and store copy are working files, not
# something anybody cloning this repo needs.
#
# Run:  scripts/screenshots.sh

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="screenshots"
BUNDLE="com.splitfree.SplitFree"
DERIVED="${TMPDIR:-/tmp}/splitfree-shots"

# The simulator renders these natively at the sizes App Store Connect wants,
# so nothing is resized afterwards and nothing is soft.
# App Store Connect shows a slot per display class and rejects anything whose
# pixel dimensions are not on its list, so each of these is rendered natively at
# a size that slot accepts rather than resized afterwards.
#
#   device                | folder      | accepted by
#   iPhone 17 Pro Max     | iphone-6.9  | 6.9 inch slot, 1320 x 2868
#   iPhone 14 Plus        | iphone-6.5  | 6.5 inch slot, 1284 x 2778
#   iPad Pro 13-inch (M5) | ipad-13     | 13 inch slot,  2064 x 2752
DEVICES=(
  "iPhone 17 Pro Max|iphone-6.9"
  "iPhone 14 Plus|iphone-6.5"
  "iPad Pro 13-inch (M5)|ipad-13"
)
BUILD_ON="iPhone 17 Pro Max"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

udid_for() {
  xcrun simctl list devices available -j | python3 -c "
import json, sys
want = sys.argv[1]
for _, devices in json.load(sys.stdin)['devices'].items():
    for d in devices:
        if d['name'] == want:
            print(d['udid']); raise SystemExit
" "$1"
}

capture() { # capture <udid> <folder>
  local udid="$1" folder="$2" name args
  mkdir -p "$OUT/$folder"

  # A real battery percentage and a stray carrier name date the images.
  xcrun simctl status_bar "$udid" override \
    --time "09:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 \
    --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true

  while IFS='|' read -r name args; do
    [ -z "$name" ] && continue
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    xcrun simctl launch "$udid" "$BUNDLE" -seedDemoData $args >/dev/null
    sleep 4
    xcrun simctl io "$udid" screenshot --type=png "$OUT/$folder/$name.png" >/dev/null
    printf '  %s\n' "$name"
  done <<'ROUTE'
1-groups|-startTab groups
2-group|-startTab groups -openFirstGroup
3-friends|-startTab friends
4-insights|-startTab insights
5-account|-startTab account
ROUTE

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
}

say "Building"
xcodebuild -project SplitFree.xcodeproj -scheme SplitFree \
  -destination "platform=iOS Simulator,name=$BUILD_ON" \
  -derivedDataPath "$DERIVED" build >/dev/null
APP="$DERIVED/Build/Products/Debug-iphonesimulator/SplitFree.app"

for pair in "${DEVICES[@]}"; do
  device="${pair%%|*}"; folder="${pair##*|}"
  say "$device"
  udid="$(udid_for "$device")"
  if [ -z "$udid" ]; then
    echo "  no simulator named '$device'; add it in Xcode under Window > Devices and Simulators" >&2
    continue
  fi
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl uninstall "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"
  capture "$udid" "$folder"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
done

say "Written"
find "$OUT" -name '*.png' | sort | while read -r f; do
  printf '  %-36s %s x %s\n' "$f" \
    "$(sips -g pixelWidth "$f" | awk '/pixelWidth/ {print $2}')" \
    "$(sips -g pixelHeight "$f" | awk '/pixelHeight/ {print $2}')"
done
