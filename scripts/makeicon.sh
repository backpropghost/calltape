#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from scripts/AppIconGen.swift.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$root/.build/AppIcon.iconset"

rm -rf "$work"
mkdir -p "$work"
swiftc -O "$root/scripts/AppIconGen.swift" -o "$root/.build/appicongen"
"$root/.build/appicongen" "$work"
iconutil -c icns "$work" -o "$root/Resources/AppIcon.icns"
echo "==> Wrote Resources/AppIcon.icns"
