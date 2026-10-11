#!/bin/bash
# Builds dist/PiNative.app (ad-hoc signed). Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG" --product PiNative
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="dist/PiNative.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PiNative" "$APP/Contents/MacOS/PiNative"
# SwiftPM resource bundles (Textual's highlighter etc.)
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
[ -f scripts/AppIcon.icns ] && cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Optional: bundle the server (see scripts/build-server.sh)
[ -d dist/server ] && cp -R dist/server "$APP/Contents/Resources/server"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>TAKT Pi GUI</string>
<key>CFBundleDisplayName</key><string>TAKT Pi GUI</string>
<key>CFBundleIdentifier</key><string>com.takt.pi-gui</string>
<key>CFBundleExecutable</key><string>PiNative</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
