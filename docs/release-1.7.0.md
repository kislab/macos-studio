## OS Studio 1.7.0 — Englisch, Fortsetzen, Yosemite bis Sierra

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.7.0/OS-Studio-1.7.0-Universal.dmg)**

- **Englische Oberfläche:** Bei englischem macOS erscheint die ganze App auf Englisch; auf Deutsch bleibt alles wie gewohnt. Ausnahme: das „Was ist neu“-Änderungsprotokoll.
- **Downloads fortsetzen:** Unterbrochene Apple-Pakete (8–17 GB) laden mit „Fortsetzen“ ab der Abbruchstelle weiter, auch nach einem Neustart der App. „Verwerfen“ löscht bereits Geladenes.
- **Behoben:** Das Fortsetzen von IPSW-Downloads schlug bisher fehl (HTTP 206 galt als Fehler).
- **OS X Yosemite, El Capitan, macOS Sierra:** Direkt von Apple als Abbild geladen, geprüft (Abbild-Prüfsumme und Paketsignatur) und ohne Administratorpasswort zur Installer-App zusammengesetzt. `createinstallmedia` bekommt bei diesen Versionen automatisch `--applicationpath`.
- **Macs mit Apple-Chip:** macOS startet dort das Intel-`createinstallmedia` von OS X 10.10 bis macOS 10.15 nicht mehr, auch nicht mit Rosetta (Korrektur zum Rosetta-Hinweis aus 1.6.0). Laden funktioniert; den USB-Stick an einem Intel-Mac erstellen. Die App prüft das vorher und verändert den Stick nicht.
- **IPSW-Prüfung:** Wartet auf Apples Firmwareliste, falls diese beim Flashen gerade lädt.

Universal für Intel und Apple Silicon, ab macOS 13. Build 48. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
