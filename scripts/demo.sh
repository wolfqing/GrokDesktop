#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product GrokDesktop

app="dist/Grok Desktop.app"
macos="$app/Contents/MacOS"
mkdir -p "$macos"
cp -f .build/debug/GrokDesktop "$macos/GrokDesktop"
if [[ ! -f "$app/Contents/Info.plist" ]]; then
  ./scripts/bundle.sh
  cp -f .build/debug/GrokDesktop "$macos/GrokDesktop"
fi
codesign --force --deep --sign - "$app" >/dev/null 2>&1 || true

pkill -x GrokDesktop 2>/dev/null || true
sleep 0.3

shot="${GROK_DESKTOP_DEMO_SHOT:-$PWD/dist/promo/grok-desktop-demo.png}"
mkdir -p "$(dirname "$shot")"

open -n "$app" --args --demo --demo-screenshot "$shot"
sleep 0.8
osascript -e 'tell application "Grok Desktop" to activate' 2>/dev/null \
  || osascript -e 'tell application "System Events" to set frontmost of first process whose name is "GrokDesktop" to true' 2>/dev/null \
  || true

echo "Opened $app --demo"
echo "Screenshot path: $shot"
