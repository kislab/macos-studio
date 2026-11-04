## OS Studio 1.1.1 — Stabilitäts- und Feinschliff

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.1.1/OS-Studio-1.1.1-Universal.dmg)**

Wartungsversion mit Verbesserungen aus einer Code-Durchsicht:

- **Flüssige Oberfläche beim Anschließen:** Das Auslesen eines iPhones/iPads (Verbinden, Kopplung, Sitzung) läuft jetzt im Hintergrund statt auf dem Haupt-Thread, das Fenster hängt dadurch nicht mehr kurz.
- **Korrekter Foto-Fortschritt:** Der Zähler „X/Y“ für die Gerätefotos zählt nur noch tatsächlich geladene Bilder und überschreitet die Gesamtzahl nicht mehr.
- **Sauberes Gerätemanagement:** Geräte werden über Apples offizielle `AMDeviceRetain`/`AMDeviceRelease` gehalten, und nicht mehr vorhandene Wiederherstellungs-Geräte werden freigegeben.

Universal für Intel und Apple Silicon, ab macOS 13. Build 34. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
