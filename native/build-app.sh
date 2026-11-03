#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64 --product MacOSStudio
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="../macOS Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacOSStudio" "$APP/Contents/MacOS/MacOSStudio"
for resource in "$BIN_DIR"/*.bundle; do
    [ ! -d "$resource" ] || ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"
done
cp ../assets/icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacOSStudio</string>
<key>CFBundleIdentifier</key><string>com.appletools.macosstudio</string>
<key>CFBundleName</key><string>macOS Studio</string>
<key>CFBundleDisplayName</key><string>macOS Studio</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'App erstellt: %s\n' "$APP"
