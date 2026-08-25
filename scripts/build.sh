#!/usr/bin/env bash
# Build CallTape.app and (optionally) install it to /Applications.
#   ./scripts/build.sh            build into dist/
#   ./scripts/build.sh --install  build, then copy to /Applications
set -euo pipefail

app="CallTape"
root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist/$app.app"
bin="$root/.build/release/$app"

echo "==> Compiling ($app)"
swift build -c release --package-path "$root"

echo "==> Assembling $app.app"
rm -rf "$dist"
mkdir -p "$dist/Contents/MacOS" "$dist/Contents/Resources"
cp "$bin" "$dist/Contents/MacOS/$app"
cp "$root/Resources/Info.plist" "$dist/Contents/Info.plist"
[ -f "$root/Resources/AppIcon.icns" ] && cp "$root/Resources/AppIcon.icns" "$dist/Contents/Resources/AppIcon.icns"

# Prefer a stable self-signed identity (permissions persist across rebuilds).
# Falls back to ad-hoc if it does not exist. Create one with make-signing-cert.sh.
sign_id="-"
sign_kind="ad-hoc (permissions reset each rebuild; run scripts/make-signing-cert.sh once to fix)"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "CallTape Local Signing"; then
    sign_id="CallTape Local Signing"
    sign_kind="stable identity ($sign_id)"
fi

echo "==> Signing: $sign_kind"
codesign --force --deep \
    --entitlements "$root/Resources/$app.entitlements" \
    --sign "$sign_id" "$dist"

echo "==> Built: $dist"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/$app.app"
    cp -R "$dist" "/Applications/$app.app"
    echo "==> Installed: /Applications/$app.app"
fi
