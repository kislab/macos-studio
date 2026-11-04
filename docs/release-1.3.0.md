## OS Studio 1.3.0 — iPhone & iPad Flasher

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.3.0/OS-Studio-1.3.0-Universal.dmg)**

**iPhone & iPad → Flasher (neu)**
- Neben „Firmware laden“ gibt es jetzt den Bereich **Flasher**: eine IPSW-Datei auf ein per USB verbundenes iPhone oder iPad installieren (Wiederherstellen).
- Funktioniert im normalen Modus, im Wiederherstellungsmodus und im DFU-Modus. Geräte werden automatisch erkannt (ECID, Modell, Name).
- Die App liest Version, Build und unterstützte Modelle aus der IPSW und erlaubt nur passende Kombinationen. Bereits geladene passende Firmware wird direkt angeboten.
- Deutliche Rückfrage vor dem Flashen – **alle Daten auf dem Gerät werden gelöscht**. Fortschritt im Fenster und am Dock-Symbol; Abbruch mit Warnung.
- Technik: Apples kostenloses **Apple Configurator** (`cfgutil restore -I`). Ist es nicht installiert, verlinkt die App den App Store. Apple muss die gewählte Version noch signieren.

Universal für Intel und Apple Silicon, ab macOS 13. Build 36. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
