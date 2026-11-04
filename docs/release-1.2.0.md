## OS Studio 1.2.0 — Prüfen, Fortsetzen, Aufräumen und mehr

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.0/OS-Studio-1.2.0-Universal.dmg)**

Umgesetzte Verbesserungen aus der Ideenliste:

**iPhone & iPad**
- **Prüfen:** Vergleicht eine geladene Firmware mit Apples veröffentlichter SHA-1-Prüfsumme und markiert beschädigte/unvollständige Dateien. (Apples Geräteliste nennt keine Dateigröße, daher Prüfung per Prüfsumme.)
- **Fortsetzen:** Abgebrochene oder fehlgeschlagene Downloads werden fortgesetzt statt komplett neu geladen (best effort über URLSession-Resume).
- **Speicherplatz-Check:** Vor dem Laden ermittelt die App die Dateigröße (HEAD-Abfrage) und warnt, wenn der Zielordner zu klein ist.
- **Aufräumen:** Ältere IPSW-Dateien im Ordner, die Apple nicht mehr listet, lassen sich gesammelt in den Papierkorb verschieben.

**Installer lokal**
- **Prüfen:** Kontrolliert die Vollständigkeit der Installationsdaten einer macOS-Installer-App.

**Allgemein**
- **Dock-Fortschritt:** Laufende Downloads und die USB-Erstellung zeigen den Prozentsatz am Dock-Symbol, auch bei verstecktem Fenster.
- **Diagnose exportieren:** Unter „Hilfe“ und in den Einstellungen sichert ein Knopf App-Version, macOS-Version, Katalogstatus und das letzte Protokoll als Textdatei.

Universal für Intel und Apple Silicon, ab macOS 13. Build 35. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
