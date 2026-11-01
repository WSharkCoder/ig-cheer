#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

cleanup() {
  rm -f tools/.make_assets tools/.make_bust_gray tools/.make_avatar
  rm -f artwork/zombie_cut.png artwork/bust_gray_5_176.png
}
trap cleanup EXIT

for tool in make_assets make_bust_gray make_avatar; do
  echo "==> $tool"
  xcrun swiftc -O "tools/$tool.swift" -o "tools/.$tool"
  "./tools/.$tool"
done

# NSImage.lockFocus() renders at the display's backing scale (2x here).
# Normalize the app icon back to a true 1024px master.
sips -z 1024 1024 assets/AppIcon1024.png >/dev/null

echo "==> Assets regenerated in assets/"
