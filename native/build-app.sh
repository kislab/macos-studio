#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64 --product MacOSStudio
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
APP="../macOS Studio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MacOSStudio" "$APP/Contents/MacOS/MacOSStudio"
for resource in "$BIN_DIR"/*.bundle; do
    [ ! -d "$resource" ] || ditto "$resource" "$APP/Contents/Resources/$(basename "$resource")"
done
SPARKLE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/MacOSStudio"
cp ../docs/licenses/AppleDB.txt "$APP/Contents/Resources/AppleDB-LICENSE.txt"
cp ../docs/licenses/Sparkle.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
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
<key>CFBundleShortVersionString</key><string>1.2.15</string>
<key>CFBundleVersion</key><string>18</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSRemovableVolumesUsageDescription</key><string>macOS Studio benötigt Zugriff auf Wechselmedien, um mit Apples createinstallmedia einen bootfähigen USB-Stick zu erstellen.</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/kislab/macos-studio/main/appcast.xml</string>
<key>SUPublicEDKey</key><string>xcZo5IOnSiJkaaCe+YyZkukO1pfn0PNEfk50dTKXJNs=</string>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUScheduledCheckInterval</key><integer>21600</integer>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUAllowsAutomaticUpdates</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'App erstellt: %s\n' "$APP"
