#!/bin/bash
# One command from a clean tree to a signed, notarised DMG.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${1:?usage: release.sh <version>}"

python3 - "$VERSION" <<'PY'
import pathlib, re, sys
version = sys.argv[1]
path = pathlib.Path("Sources/VoltaicaCore/Version.swift")
text = path.read_text()
text = re.sub(r'marketing = "[^"]*"', f'marketing = "{version}"', text)
path.write_text(text)
PY

swift test
./Scripts/make-icns.sh
./Scripts/build.sh
./Scripts/dmg.sh "$VERSION"

DMG="build/Voltaica-$VERSION.dmg"
if security find-identity -v | grep -q "Developer ID Application"; then
  ./Scripts/notarize.sh "$DMG"
else
  echo "!! no Developer ID certificate: $DMG is signed but NOT notarised" >&2
fi

echo
echo "Release $VERSION ready:"
shasum -a 256 "$DMG"
