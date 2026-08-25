#!/usr/bin/env bash
# Build CallTape.app and package it into a styled drag-to-install .dmg.
#
#   ./scripts/package-dmg.sh
#
# Output: dist/CallTape.dmg
#
# The install window opens with a background that reads "Drag CallTape to
# Applications", the app icon on the left, and the Applications folder on the
# right, so the whole install is one obvious drag.
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
vol="CallTape"
root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"

echo "==> Building $app.app"
"$root/scripts/build.sh"

echo "==> Rendering install-window background"
bgdir="$(mktemp -d)"
trap 'rm -rf "$bgdir" "${stage:-}" "${rwdmg:-}"' EXIT
swift "$root/scripts/dmg-background.swift" 1 "$bgdir/bg.png"
swift "$root/scripts/dmg-background.swift" 2 "$bgdir/bg@2x.png"
tiffutil -cathidpicheck "$bgdir/bg.png" "$bgdir/bg@2x.png" -out "$bgdir/background.tiff" >/dev/null

echo "==> Staging DMG contents"
stage="$(mktemp -d)"
cp -R "$dist/$app.app" "$stage/"
ln -s /Applications "$stage/Applications"
mkdir "$stage/.background"
cp "$bgdir/background.tiff" "$stage/.background/background.tiff"

echo "==> Creating writable image"
rwdmg="$(mktemp -u).dmg"
hdiutil create -volname "$vol" -srcfolder "$stage" -ov -format UDRW "$rwdmg" >/dev/null

echo "==> Styling install window"
device="$(hdiutil attach -readwrite -noverify -noautoopen "$rwdmg" | egrep '^/dev/' | head -1 | awk '{print $1}')"
mount="/Volumes/$vol"
# Give Finder a moment to mount before scripting it.
until [ -d "$mount" ]; do sleep 0.2; done

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$vol"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set position of item "$app.app" of container window to {175, 195}
    set position of item "Applications" of container window to {485, 195}
    set background picture of opts to POSIX file "$mount/.background/background.tiff"
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Persist the layout, then release the image.
sync
hdiutil detach "$device" >/dev/null

dmg="$dist/$app.dmg"
rm -f "$dmg"
echo "==> Compressing $dmg"
hdiutil convert "$rwdmg" -format UDZO -imagekey zlib-level=9 -ov -o "$dmg" >/dev/null

echo "==> Done: $dmg"
