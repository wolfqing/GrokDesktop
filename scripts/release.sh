#!/bin/zsh
set -euo pipefail

# Build, optionally Developer-ID sign + notarize, optionally publish a GitHub Release.
#
#   ./scripts/release.sh              # zip only
#   ./scripts/release.sh --publish    # zip + gh release v$VERSION
#
# Signing / notarization (optional, skipped when missing):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE="notarytool-profile"   # created with: xcrun notarytool store-credentials

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="${VERSION:-0.1.15}"
publish=0
for arg in "$@"; do
  case "$arg" in
    --publish) publish=1 ;;
    --version=*) version="${arg#--version=}" ;;
  esac
done

echo "==> bundle $version"
VERSION="$version" "$root/scripts/bundle.sh"

app="$root/dist/Grok Desktop.app"
zip="$root/dist/Grok-Desktop-${version}.zip"
entitlements="$root/scripts/GrokDesktop.entitlements"

identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'\"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "$identity" ]]; then
  echo "==> codesign as $identity"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$entitlements" \
    --sign "$identity" \
    "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
else
  echo "==> no Developer ID Application identity; leaving unsigned"
fi

if [[ -n "${NOTARY_PROFILE:-}" && -n "$identity" ]]; then
  echo "==> notarize with profile $NOTARY_PROFILE"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"
  echo "==> stapled $zip"
else
  echo "==> skip notarization (set NOTARY_PROFILE and SIGN_IDENTITY)"
fi

echo "App: $app"
echo "Zip: $zip"

if (( publish )); then
  if ! command -v gh >/dev/null; then
    echo "gh is not installed" >&2
    exit 1
  fi
  notes="$(cat <<EOF
Community macOS client for Grok Build. Not an official xAI product.

Install the official CLI first:

\`\`\`
curl -fsSL https://x.ai/cli/install.sh | bash
grok login
\`\`\`

This build is unsigned unless the notes say otherwise. First open: right-click the app → Open.
EOF
)"
  if gh release view "v${version}" >/dev/null 2>&1; then
    echo "==> update existing release v${version}"
    gh release upload "v${version}" "$zip" --clobber
  else
    echo "==> create GitHub release v${version}"
    gh release create "v${version}" "$zip" \
      --title "Grok Desktop ${version}" \
      --notes "$notes"
  fi
  gh release view "v${version}" --json url -q .url
fi
