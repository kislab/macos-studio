## OS Studio 1.2.27 — Extras (Wiederherstellungs- & DFU-Modus) und Einstellungen

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.27/OS-Studio-1.2.27-Universal.dmg)**

**Extras**
- Angeschlossene iPhones und iPads werden mit Name, Modell, iOS-Version und Foto erkannt.
- **Wiederherstellungsmodus per Klick:** Das Gerät startet ohne Tastenkombination neu und zeigt Laptop und Kabel. Es wird nichts gelöscht. Voraussetzung: Das Gerät vertraut diesem Mac („Vertrauen“ wurde getippt).
- **Normal starten:** Holt ein Gerät aus dem Wiederherstellungsmodus wieder heraus.
- **DFU-Modus mit Anleitung:** DFU lässt sich bei iPhone und iPad nur über die Tasten am Gerät auslösen. Die App wählt die Tastenfolge für das Modell (iPhone 8 und neuer, iPhone 7, ältere iPhones/iPod touch, iPad mit und ohne Home-Taste), zeigt jeden Schritt mit Countdown und meldet den DFU-Modus, sobald er über USB erkannt wird.
- Technik: Apples Geräte-Framework von macOS (dasselbe wie der Finder) und die USB-Kennungen der Geräte (DFU `0x1227`, Wiederherstellung `0x1281`). Es wird nichts zusätzlich installiert. Das Framework ist nicht öffentlich dokumentiert; fehlt es, funktioniert die Erkennung von DFU und Wiederherstellung trotzdem.

**Einstellungen** (Seitenleiste oder ⌘,)
- Automatisch nach Updates suchen, Neuigkeiten nach einem Update anzeigen, „Jetzt nach Updates suchen“.
- Installer für andere Macs ein- oder ausblenden.
- Speicherort für iPhone-/iPad-Firmware, Gerätefotos ein/aus, Foto-Zwischenspeicher leeren.
- Alle Einstellungen zurücksetzen (geladene Dateien bleiben unverändert).

Universal ab macOS 13, Build 30. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
