#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/macOS Studio.app"
OUTPUT="$PWD/macOS-Studio-1.2.6-Universal.dmg"
if [ ! -x "$APP/Contents/MacOS/MacOSStudio" ]; then
    ./native/build-app.sh
fi
codesign --verify --deep --strict "$APP"
ARCHS="$(lipo -archs "$APP/Contents/MacOS/MacOSStudio")"
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] || { echo 'Universal-Build fehlt.' >&2; exit 1; }
if [ -e "$OUTPUT" ]; then
    printf 'DMG existiert bereits: %s\nBitte vor einem neuen Build umbenennen.\n' "$OUTPUT" >&2
    exit 1
fi
mkdir -p dist
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/macos-studio-dmg.XXXXXX")"
ditto "$APP" "$STAGING/macOS Studio.app"
ln -s /Applications "$STAGING/Programme"
cat > "$STAGING/Installation.txt" <<'TXT'
macOS Studio 1.2.6 — Universal für Intel und Apple Silicon

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
shasum -a 256 "$(basename "$OUTPUT")" > "$OUTPUT.sha256"
printf 'Fertig: %s\n' "$OUTPUT"
