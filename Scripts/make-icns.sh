#!/bin/bash
# Renders the icon and packs it into Resources/Voltaica.icns
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift Scripts/make-icon.swift
SET="build/Voltaica.iconset"
rm -rf "$SET"; mkdir -p "$SET"

for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  size="${spec%% *}"
  name="${spec##* }"
  sips -z "$size" "$size" build/icon-1024.png --out "$SET/$name.png" >/dev/null
done

iconutil -c icns "$SET" -o Resources/Voltaica.icns
echo "==> Resources/Voltaica.icns ($(du -h Resources/Voltaica.icns | cut -f1))"
