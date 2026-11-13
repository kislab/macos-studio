#!/bin/bash
# Build first. This script signs an update using the private key in login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/OS Studio.app"
TOOLS="$PWD/native/.build/artifacts/sparkle/Sparkle/bin"
ACCOUNT="macos-studio-kislab"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ && "$BUILD" =~ ^[0-9]+$ ]] || exit 1
[[ "$("$TOOLS/generate_keys" --account "$ACCOUNT" -p)" == "$PUBLIC_KEY" ]] || { echo 'Signing key does not match app.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
ARCHIVE_NAME="OS-Studio-$VERSION-Universal.zip"
ARCHIVE="dist/$ARCHIVE_NAME"
mkdir -p dist
[ ! -e "$ARCHIVE" ] || { echo "Archive already exists: $ARCHIVE" >&2; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
SIGNATURE="$("$TOOLS/sign_update" --account "$ACCOUNT" -p "$ARCHIVE")"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$ARCHIVE" "$SIGNATURE"
LENGTH="$(stat -f %z "$ARCHIVE")"
# Tags are v<marketing-version>.0 for two-component marketing versions.
TAG="v$VERSION"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]] && TAG="$TAG.0"
NOTES="docs/release-$VERSION.md"
NOTES_EN="docs/release-$VERSION.en.md"
[ -f "$NOTES" ] || { echo "Release notes missing: $NOTES" >&2; exit 1; }
NOTES_HTML="$(/usr/bin/python3 -I native/scripts/release-notes-html.py "$NOTES")"
DESCRIPTIONS="      <description sparkle:descriptionFormat=\"html\"><![CDATA[$NOTES_HTML]]></description>"
if [ -f "$NOTES_EN" ]; then
  NOTES_EN_HTML="$(/usr/bin/python3 -I native/scripts/release-notes-html.py "$NOTES_EN")"
  DESCRIPTIONS="$DESCRIPTIONS
      <description xml:lang=\"en\" sparkle:descriptionFormat=\"html\"><![CDATA[$NOTES_EN_HTML]]></description>"
fi
cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>OS Studio Updates</title>
    <link>https://github.com/kislab/macos-studio</link>
    <description>Signierte Updates für OS Studio</description>
    <language>de</language>
    <item>
      <title>OS Studio $VERSION</title>
$DESCRIPTIONS
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/kislab/macos-studio/releases/download/$TAG/$ARCHIVE_NAME" sparkle:edSignature="$SIGNATURE" length="$LENGTH" type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
"$TOOLS/sign_update" --account "$ACCOUNT" appcast.xml
"$TOOLS/sign_update" --account "$ACCOUNT" --verify appcast.xml
(cd dist && shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256")
printf 'Signed update ready: %s (publish release before pushing appcast.xml)\n' "$ARCHIVE"
