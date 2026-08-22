#!/bin/bash
# Packs build/Voltaica.app into a DMG with an Applications symlink.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(grep -o 'marketing = "[^"]*"' Sources/VoltaicaCore/Version.swift | cut -d'"' -f2)}"
APP="build/Voltaica.app"
[[ -d "$APP" ]] || { echo "build $APP first (./Scripts/build.sh)" >&2; exit 1; }

STAGE="build/dmg"
DMG="build/Voltaica-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp README.md "$STAGE/Read me first.md"

hdiutil create -volname "Voltaica $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
  -fs HFS+ -imagekey zlib-level=9 "$DMG" >/dev/null

IDENTITY="${VOLTAICA_IDENTITY:-$(./Scripts/pick-identity.sh)}"
if [[ "$IDENTITY" != "-" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

rm -rf "$STAGE"
echo "==> $DMG"
shasum -a 256 "$DMG"
