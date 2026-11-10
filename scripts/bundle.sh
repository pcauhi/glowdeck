#!/usr/bin/env bash
# Builds Glowdeck.app into ./build. Usage: scripts/bundle.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
# The Command Line Tools ship no SwiftUI macro plugin for the macOS 27 SDK, so prefer a 26.x SDK
# when building without Xcode. With Xcode installed this is unnecessary.
if [[ -z "${SDKROOT:-}" ]] && ! xcode-select -p | grep -q Xcode.app; then
  SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
  [[ -n "$SDK" ]] && export SDKROOT="$SDK"
fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" || { ARCHS=(); swift build -c release; }
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Glowdeck"
[[ -f "$BIN" ]] || { echo "Built binary not found at $BIN" >&2; exit 1; }

APP=build/Glowdeck.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glowdeck"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Glowdeck</string>
  <key>CFBundleDisplayName</key><string>Glowdeck</string>
  <key>CFBundleIdentifier</key><string>app.glowdeck.Glowdeck</string>
  <key>CFBundleExecutable</key><string>Glowdeck</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>Glowdeck finds and controls smart lights (Hue, LIFX, WiZ, WLED, Govee, Nanoleaf…) on your local network.</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_hue._tcp</string><string>_wled._tcp</string><string>_elg._tcp</string>
    <string>_nanoleafapi._tcp</string><string>_home-assistant._tcp</string>
  </array>
</dict></plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Glowdeck 2>/dev/null || true
  rm -rf /Applications/Glowdeck.app
  cp -R "$APP" /Applications/
  open /Applications/Glowdeck.app
  echo "Installed to /Applications and launched"
fi
