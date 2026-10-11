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
[ -f scripts/browser-server.mjs ] && cp scripts/browser-server.mjs "$APP/Contents/Resources/browser-server.mjs"
# A copy of node named after the app. macOS permission prompts show the executable's name, so the
# sidecar and the headless browser are attributed to "TAKT Pi" instead of "node".
NODE_BIN="$(command -v node || true)"
if [ -n "$NODE_BIN" ]; then
  # Homebrew's node on PATH is a small stub; the real binary lives in the Cellar and is what
  # actually runs. Copy that, or the helper cannot find libnode.
  REAL_NODE="$(readlink -f "$NODE_BIN")"
  mkdir -p "$APP/Contents/Helpers"
  # A symlink, not a copy: node dynamically links libnode and Homebrew libraries that live next to
  # it, so a copied binary cannot start. The link's name is what permission prompts display.
  ln -sfn "$REAL_NODE" "$APP/Contents/Helpers/TAKT Pi"
fi
# Optional: bundle the server (see scripts/build-server.sh)
[ -d dist/server ] && cp -R dist/server "$APP/Contents/Resources/server"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>TAKT Pi</string>
<key>CFBundleDisplayName</key><string>TAKT Pi</string>
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
