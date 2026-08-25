#!/usr/bin/env bash
# Build CallTape.app and package it into a drag-to-install .dmg.
#
#   ./scripts/package-dmg.sh
#
# Output: dist/CallTape.dmg
#
# NOTE ON DISTRIBUTION:
# This produces an unsigned (or self-signed) DMG. macOS Gatekeeper will warn on
# first open, and users must right-click > Open the first time. For a smooth,
# warning-free install you need an Apple Developer ID ($99/yr): sign with
#   codesign --deep --options runtime --timestamp -s "Developer ID Application: NAME" CallTape.app
# then notarize + staple:
#   xcrun notarytool submit CallTape.dmg --keychain-profile "AC" --wait
#   xcrun stapler staple CallTape.dmg
set -euo pipefail

app="CallTape"
root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"

echo "==> Building $app.app"
"$root/scripts/build.sh"

echo "==> Staging DMG contents"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$dist/$app.app" "$stage/"
ln -s /Applications "$stage/Applications"   # drag-to-install target

dmg="$dist/$app.dmg"
rm -f "$dmg"
echo "==> Creating $dmg"
hdiutil create -volname "$app" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null

echo "==> Done: $dmg"
