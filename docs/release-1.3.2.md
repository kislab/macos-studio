## OS Studio 1.3.2 — Fehlerbehebungen

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.3.2/OS-Studio-1.3.2-Universal.dmg)**

- **USB-Erstellung:** Wird das Terminal-Fenster nach „Abbrechen“ geschlossen, wartet die App nicht mehr endlos, sondern meldet den Abbruch nach spätestens einer Minute.
- **iPhone & iPad:** Ungültige Fortsetzungsdaten eines abgebrochenen Downloads werden verworfen – der nächste Versuch startet sauber neu, statt jedes Mal zu scheitern.
- **„Abbrechen“** im Fortschrittsbereich erscheint nur noch, wenn wirklich ein macOS-Download läuft (nicht während IPSW-Download, Flashen oder Löschen).
- **Werkzeug-Ausgaben:** Die letzten Zeilen, die ein Apple-Werkzeug kurz vor dem Beenden schreibt (oft die Fehlermeldung), gehen nicht mehr verloren.
- **Apple-Katalog:** gzip-Kopfdaten mit Zusatzfeld werden korrekt gelesen.

Universal für Intel und Apple Silicon, ab macOS 13. Build 38. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
