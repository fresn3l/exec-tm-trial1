#!/bin/zsh
# Builds a sandboxed, ad-hoc-signed Spike.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=Spike.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
cp .build/release/Spike $APP/Contents/MacOS/Spike
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.execfn.spike</string>
  <key>CFBundleName</key><string>Spike</string>
  <key>CFBundleExecutable</key><string>Spike</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
codesign --force --sign - --entitlements Spike.entitlements $APP
codesign -d --entitlements - $APP 2>/dev/null | grep -q app-sandbox && echo "Built $PWD/$APP (sandboxed)"
