#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DIST="$PWD/dist"
APP="$DIST/OS Studio.app"
if [ ! -x "$APP/Contents/MacOS/MacOSStudio" ]; then
    ./native/build-app.sh
fi
codesign --verify --deep --strict "$APP"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/MacOSStudio")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || { echo 'Universal-Build fehlt.' >&2; exit 1; }
# Version comes from the built app, so this script never needs a manual bump.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || { echo "Ungültige Version: $VERSION" >&2; exit 1; }
NAME="OS-Studio-$VERSION-Universal"
OUTPUT="$DIST/$NAME.dmg"
if [ -e "$OUTPUT" ]; then
    printf 'DMG existiert bereits: %s\nVeröffentlichte Versionen nicht überschreiben; Version erhöhen.\n' "$OUTPUT" >&2
    exit 1
fi
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/macos-studio-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/OS Studio.app"
ln -s /Applications "$STAGING/Programme"
cat > "$STAGING/Installation.txt" <<TXT
OS Studio $VERSION — Universal für Intel und Apple Silicon

Installation:
1. „OS Studio.app“ auf „Programme“ ziehen.
2. Nach dem Kopieren dieses Laufwerk auswerfen.
3. OS Studio aus dem Programme-Ordner öffnen.

Voraussetzung: macOS 13 Ventura oder neuer.
Python oder zusätzliche Pakete werden nicht benötigt.

Dieser Build ist lokal ad-hoc signiert, aber nicht mit einer Apple Developer ID
signiert und nicht notarisiert. Bei der Übertragung auf einen anderen Mac kann
macOS deshalb eine Sicherheitsprüfung bzw. Warnung anzeigen.

Die GB-Anzeige ist eine Schätzung aus Apples Fortschrittsangaben.
Die USB-Erstellung löscht das ausgewählte Ziel-Volume nach Bestätigung.
TXT
hdiutil create -volname 'OS Studio installieren' -srcfolder "$STAGING" -format UDZO -imagekey zlib-level=9 "$OUTPUT"
hdiutil verify "$OUTPUT"
cd "$DIST"
shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256"
# Combined checksum file for the GitHub release (DMG and, if prepared, the update ZIP).
if [ -e "$NAME.zip" ]; then shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt
else shasum -a 256 "$NAME.dmg" > SHA256SUMS.txt; fi
# Keep the three most recently built versions in dist/ (by file time, so a reset version
# number like 1.0 after 1.2.x is still kept). Both name prefixes count toward the three.
VERSIONS="$( { ls -t OS-Studio-*-Universal.* macOS-Studio-*-Universal.* 2>/dev/null || true; } | sed -E 's/^(mac)?OS-Studio-(.+)-Universal\..*$/\2/' | awk '!seen[$0]++')"
printf '%s\n' "$VERSIONS" | tail -n +4 | while IFS= read -r old; do
    [ -n "$old" ] || continue
    for prefix in OS-Studio macOS-Studio; do
        rm -f "$prefix-$old-Universal.dmg" "$prefix-$old-Universal.dmg.sha256" \
              "$prefix-$old-Universal.zip" "$prefix-$old-Universal.zip.sha256"
    done
    printf 'Alte Version entfernt: %s\n' "$old"
done
printf 'Fertig: %s\n' "$OUTPUT"
