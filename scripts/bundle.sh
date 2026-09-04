#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="${VERSION:-0.1.22}"

swift build -c release --product GrokDesktop

bin="$root/.build/release/GrokDesktop"
app="$root/dist/Grok Desktop.app"
macos="$app/Contents/MacOS"
res="$app/Contents/Resources"

rm -rf "$app"
mkdir -p "$macos" "$res"
cp "$bin" "$macos/GrokDesktop"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>GrokDesktop</string>
  <key>CFBundleIdentifier</key>
  <string>com.wolfqing.GrokDesktop</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Grok Desktop</string>
  <key>CFBundleDisplayName</key>
  <string>Grok Desktop</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSUserNotificationsUsageDescription</key>
  <string>Grok Desktop notifies you when a session needs approval or an answer.</string>
</dict>
</plist>
PLIST

# Bind Info.plist into an adhoc signature so Finder / `open` accepts the bundle.
# Linker-signed binaries leave the plist unbound and can fail to launch after zip.
codesign --force --deep --sign - "$app"
xattr -cr "$app" || true

zip="$root/dist/Grok-Desktop-${version}.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xattr -cr "$zip" || true
echo "Built $app"
echo "Zipped $zip"
