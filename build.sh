#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="IG应援"
APP="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP/Contents"
BIN="$CONTENTS/MacOS/IGCheer"

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Compiling Swift"
xcrun swiftc -O -swift-version 5 \
  "$ROOT/Sources/main.swift" \
  "$ROOT/Sources/Models.swift" \
  "$ROOT/Sources/PredictionClient.swift" \
  "$ROOT/Sources/ModelCatalogClient.swift" \
  "$ROOT/Sources/PanelWebView.swift" \
  "$ROOT/Sources/SettingsView.swift" \
  -o "$BIN" \
  -framework Cocoa -framework WebKit -framework CryptoKit

echo "==> Bundling resources"
cp "$ROOT/assets/avatar_bust_white.png" "$CONTENTS/Resources/avatar_bust_white.png"
cp "$ROOT/assets/MenuIconGrayBust.png" "$CONTENTS/Resources/MenuIconGrayBust.png"
cp "$ROOT/assets/MenuIconGrayBust@2x.png" "$CONTENTS/Resources/MenuIconGrayBust@2x.png"
cp "$ROOT/assets/MenuIconGrayBust@3x.png" "$CONTENTS/Resources/MenuIconGrayBust@3x.png"
cp "$ROOT/Sources/panel.html" "$CONTENTS/Resources/panel.html"
cp "$ROOT/Sources/panel.css" "$CONTENTS/Resources/panel.css"
cp "$ROOT/Sources/panel.js" "$CONTENTS/Resources/panel.js"
cp "$ROOT/tools/fetch_schedule.py" "$CONTENTS/Resources/fetch_schedule.py"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# App icon (.icns)
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" \
            "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" \
            "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  set -- $spec
  sips -z "$1" "$1" "$ROOT/assets/AppIcon1024.png" --out "$ICONSET/$2" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.wsharkcoder.igcheer</string>
    <key>CFBundleExecutable</key>
    <string>IGCheer</string>
    <key>CFBundleName</key>
    <string>IG应援</string>
    <key>CFBundleDisplayName</key>
    <string>IG 应援</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.2</string>
    <key>CFBundleVersion</key>
    <string>14</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSHumanReadableCopyright</key>
    <string>Made with love for Invictus Gaming.</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.wsharkcoder.igcheer.url</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>igcheer</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Installing to /Applications"
if pgrep -x IGCheer >/dev/null 2>&1; then
  pkill -x IGCheer || true
  sleep 0.4
fi
rm -rf "/Applications/$APP_NAME.app"
ditto "$APP" "/Applications/$APP_NAME.app"

echo "Built: /Applications/$APP_NAME.app"
ls -ld "/Applications/$APP_NAME.app"
