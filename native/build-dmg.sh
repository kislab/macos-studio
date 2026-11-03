#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DIST="$PWD/dist"
APP="$DIST/macOS Studio.app"
if [ ! -x "$APP/Contents/MacOS/MacOSStudio" ]; then
    ./native/build-app.sh
fi
codesign --verify --deep --strict "$APP"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/MacOSStudio")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || { echo 'Universal-Build fehlt.' >&2; exit 1; }
# Version comes from the built app, so this script never needs a manual bump.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Ungültige Version: $VERSION" >&2; exit 1; }
NAME="macOS-Studio-$VERSION-Universal"
OUTPUT="$DIST/$NAME.dmg"
if [ -e "$OUTPUT" ]; then
    printf 'DMG existiert bereits: %s\nVeröffentlichte Versionen nicht überschreiben; Version erhöhen.\n' "$OUTPUT" >&2
    exit 1
fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/macos-studio-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/macOS Studio.app"
ln -s /Applications "$STAGING/Programme"
cat > "$STAGING/Installation.txt" <<TXT
macOS Studio $VERSION — Universal für Intel und Apple Silicon

Installation:
1. „macOS Studio.app“ auf „Programme“ ziehen.
2. Nach dem Kopieren dieses Laufwerk auswerfen.
3. macOS Studio aus dem Programme-Ordner öffnen.

Voraussetzung: macOS 13 Ventura oder neuer.
Python oder zusätzliche Pakete werden nicht benötigt.

Dieser Build ist lokal ad-hoc signiert, aber nicht mit einer Apple Developer ID
signiert und nicht notarisiert. Bei der Übertragung auf einen anderen Mac kann
macOS deshalb eine Sicherheitsprüfung bzw. Warnung anzeigen.

Die GB-Anzeige ist eine Schätzung aus Apples Fortschrittsangaben.
Die USB-Erstellung löscht das ausgewählte Ziel-Volume nach Bestätigung.
TXT
hdiutil create -volname 'macOS Studio installieren' -srcfolder "$STAGING" -format UDZO -imagekey zlib-level=9 "$OUTPUT"
hdiutil verify "$OUTPUT"
cd "$DIST"
shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256"
# Combined checksum file for the GitHub release (DMG and, if prepared, the update ZIP).
if [ -e "$NAME.zip" ]; then shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt
else shasum -a 256 "$NAME.dmg" > SHA256SUMS.txt; fi
# Keep only the three newest versions of build artifacts in dist/.
OLD="$(ls macOS-Studio-*-Universal.* 2>/dev/null | sed -E 's/^macOS-Studio-(.+)-Universal\..*$/\1/' | sort -u -V | sed -e :a -e '$d;N;2,3ba' -e 'P;D')"
for old in $OLD; do
    rm -f "macOS-Studio-$old-Universal.dmg" "macOS-Studio-$old-Universal.dmg.sha256" \
          "macOS-Studio-$old-Universal.zip" "macOS-Studio-$old-Universal.zip.sha256"
    printf 'Alte Version entfernt: %s\n' "$old"
done
printf 'Fertig: %s\n' "$OUTPUT"
