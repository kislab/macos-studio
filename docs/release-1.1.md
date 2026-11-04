## OS Studio 1.1 — Foto-Cache mit Fortschritt und Mac-DFU über USB-C

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.1.0/OS-Studio-1.1-Universal.dmg)**

**iPhone & iPad**
- Gerätefotos werden mit sichtbarem Fortschritt geladen („X/Y“) und auf dem Mac zwischengespeichert.
- Bereits vorhandene Fotos werden übersprungen, der Start bleibt schnell und funktioniert danach offline.

**Extras: Mac in DFU versetzen (USB-C)**
- Ein Apple-Silicon-Mac kann einen zweiten, über den DFU-Port per USB-C/Thunderbolt verbundenen Mac **in den DFU-Modus versetzen** oder **neu starten** – per Klick, ohne Tastenkombination.
- Technik: Vendor-Defined Message über den USB-C-Controller (AppleHPM), nachgebaut nach dem Open-Source-Werkzeug macvdmtool (Apache-2.0). Läuft über einen kurzen, mit Administratorrechten gestarteten Helfer der App selbst.
- **Grenzen:** Nur Apple Silicon, nur am DFU-Port, nicht über einen USB-Hub. **Für iPhone und iPad funktioniert es nicht** – dort nur der geführte DFU-Ablauf über die Tasten. Die Funktion ist als experimentell gekennzeichnet und wird vor dem Senden abgesichert; passiert nichts am eigenen Mac, wenn kein Gerät am DFU-Port hängt.

Universal für Intel und Apple Silicon, ab macOS 13. Build 33. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
