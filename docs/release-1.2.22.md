## macOS Studio 1.2.22 — Seriennummer direkt in der App

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.22/macOS-Studio-1.2.22-Universal.dmg)**

**Mac suchen**
- Bisher öffnete eine Seriennummer automatisch Apples Website (auch beim Drücken von Enter). Das passiert nicht mehr; die Suche bleibt in der App.
- Seriennummern bis 2021 (11 oder 12 Zeichen) enthalten einen Konfigurationscode. Die App fragt damit Apples öffentliche Modellabfrage ab (`support-sp.apple.com`, es wird nur der Code aus 3–4 Zeichen gesendet, nicht die ganze Seriennummer) und zeigt das passende Modell aus der Datenbank.
- Seit 2021 vergibt Apple zufällige 10-stellige Seriennummern ohne Modellinformation. Dafür gibt es keine öffentliche Abfrage; die App erklärt das und verweist auf Modellnummer, Modellkennung oder „Meinen Mac erkennen“.

Universal ab macOS 13, Build 25. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
