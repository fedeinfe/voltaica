#!/bin/bash
# Notarises and staples a DMG. Needs a Developer ID Application certificate and a stored
# notarytool profile; both are one-time setup, see docs/BUILDING.md.
set -euo pipefail
DMG="${1:?usage: notarize.sh <dmg>}"
PROFILE="${VOLTAICA_NOTARY_PROFILE:-voltaica-notary}"

if ! security find-identity -v | grep -q "Developer ID Application"; then
  cat >&2 <<'MSG'
No Developer ID Application certificate in the keychain.

Create one once, then re-run:
  Xcode › Settings › Accounts › (Federico Infelici) › Manage Certificates › + ›
  Developer ID Application

Apple Development certificates cannot notarise: macOS will still run the app, but every
other Mac shows the "unidentified developer" warning.
MSG
  exit 1
fi

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
echo "==> notarised and stapled: $DMG"
