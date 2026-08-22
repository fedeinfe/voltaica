#!/bin/bash
# Builds Voltaica.app from the Swift package: universal binaries, bundle layout, signing.
#
#   ./Scripts/build.sh                  release build, signed with whatever identity is found
#   ./Scripts/build.sh --debug          faster build, ad-hoc signature
#   ./Scripts/build.sh --identity "..." pick a signing identity explicitly
#   ./Scripts/build.sh --no-universal   host architecture only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG=release
UNIVERSAL=1
IDENTITY="${VOLTAICA_IDENTITY:-}"
TEAM_ID="68438RG5HP"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG=debug; shift ;;
    --no-universal) UNIVERSAL=0; shift ;;
    --identity) IDENTITY="$2"; shift 2 ;;
    --adhoc) IDENTITY="-"; shift ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

VERSION=$(grep -o 'marketing = "[^"]*"' Sources/VoltaicaCore/Version.swift | cut -d'"' -f2)
BUILD=$(grep -o 'build = "[^"]*"' Sources/VoltaicaCore/Version.swift | cut -d'"' -f2)
APP="$ROOT/build/Voltaica.app"

echo "==> Voltaica $VERSION ($BUILD), $CONFIG"

if [[ $UNIVERSAL -eq 1 ]]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
else
  ARCH_FLAGS=""
fi

for product in Voltaica VoltaicaHelper voltaicactl; do
  # shellcheck disable=SC2086
  swift build -c "$CONFIG" $ARCH_FLAGS --product "$product"
done
# shellcheck disable=SC2086
BIN_DIR=$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)
echo "==> binaries in $BIN_DIR"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"

install -m 755 "$BIN_DIR/Voltaica" "$APP/Contents/MacOS/Voltaica"
install -m 755 "$BIN_DIR/VoltaicaHelper" "$APP/Contents/MacOS/VoltaicaHelper"
install -m 755 "$BIN_DIR/voltaicactl" "$APP/Contents/MacOS/voltaicactl"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
  Resources/Info-app.plist.in > "$APP/Contents/Info.plist"
install -m 644 Resources/com.federicoinfelici.Voltaica.Helper.plist \
  "$APP/Contents/Library/LaunchDaemons/com.federicoinfelici.Voltaica.Helper.plist"

if [[ -f Resources/Voltaica.icns ]]; then
  install -m 644 Resources/Voltaica.icns "$APP/Contents/Resources/Voltaica.icns"
fi
if [[ -f LICENSE ]]; then
  install -m 644 LICENSE "$APP/Contents/Resources/LICENSE"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Pick a signing identity for our team: Developer ID for anything shipped, a development
# certificate for local testing, ad-hoc as a last resort (the daemon will refuse to install).
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$("$ROOT/Scripts/pick-identity.sh" "$TEAM_ID")
fi
echo "==> signing with: $IDENTITY"

SIGN_ARGS=(--force --timestamp --options runtime)
if [[ "$IDENTITY" == "-" ]]; then
  SIGN_ARGS=(--force)
  echo "!!  ad-hoc signature: the background service will refuse to install"
fi

# Nested code first, each with its own identifier so the XPC requirements can name them.
codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" \
  --identifier com.federicoinfelici.Voltaica.Helper "$APP/Contents/MacOS/VoltaicaHelper"
codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" \
  --identifier com.federicoinfelici.Voltaica.cli "$APP/Contents/MacOS/voltaicactl"
codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" \
  --identifier com.federicoinfelici.Voltaica "$APP"

codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
echo "==> $APP"
