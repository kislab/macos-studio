## OS Studio 1.6.0 — ältere Installer und Prüfsummen

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.6.0/OS-Studio-1.6.0-Universal.dmg)**

- **High Sierra, Mojave, Catalina:** Die Versionen 10.13 bis 10.15 kommen jetzt direkt aus Apples Katalog, auch wenn Apple sie diesem Mac nicht mehr anbietet. Jede Datei wird gegen Apples Prüfdaten geprüft. Die Installer-App wird ohne Administratorpasswort zusammengesetzt.
- **Prüfsumme für macOS-Pakete:** Auch `InstallAssistant.pkg` (macOS 11 und neuer) wird nach dem Download mit Apples SHA-256-Prüfdaten verglichen.
- **IPSW-Prüfung vor dem Flashen:** Die Firmware wird vor jedem Flashen mit Apples SHA-1 verglichen, auch bei selbst gewählten Dateien. Ist sie beschädigt, bleibt das Gerät unverändert.
- **Rosetta-Hinweis:** Braucht ein älterer Installer auf einem Mac mit Apple-Chip Rosetta, meldet die App das, bevor der USB-Stick gelöscht wird.

Universal für Intel und Apple Silicon, ab macOS 13. Build 47. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
