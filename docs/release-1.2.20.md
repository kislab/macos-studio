## macOS Studio 1.2.20 — Golden Gate, neue Macs und sicherere USB-Erstellung

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.20/macOS-Studio-1.2.20-Universal.dmg)**

**Mac-Datenbank**
- macOS 27 „Golden Gate“ fehlte bei allen Modellen. Mit gewähltem Ziel-Mac wurden macOS-27-Installer deshalb ausgeblendet. Laut [Apples Kompatibilitätsliste](https://support.apple.com/en-us/127255) unterstützen alle Apple-Silicon-Macs Golden Gate, Intel-Macs nicht.
- Neu: MacBook Pro 14" M5 (2025), MacBook Pro 14"/16" M5 Pro/Max (2026), MacBook Air 13"/15" M5 (2026), MacBook Neo (2026), Mac Studio (2025, M4 Max/M3 Ultra), Mac Studio (2026, M5 Max/Ultra), Mac mini (2026, M6/M5 Pro). Modellkennungen laut Apple-Support; beim MacBook Neo laut AppleDB.

**USB erstellen**
- „Abbrechen“ ersetzt „Warten beenden“ und stoppt den Vorgang wirklich: Vor dem Löschen endet er ohne Änderung, auch wenn das Passwort erst später eingegeben wird. Läuft createinstallmedia bereits, wird es beendet; der Stick muss dann neu erstellt werden.
- Größenprüfung vor dem Start: mindestens 16 GB bzw. Installergröße plus 1,5 GB.
- Rechteprüfung vor dem Löschen: Der Vorgang schreibt zuerst eine Testdatei auf den Stick. Verweigert macOS Terminal den Zugriff, bricht er ab, bevor etwas gelöscht wird, und die App bietet die Datenschutzeinstellungen an.

**Weiteres**
- Sparkle-Update-Dialoge und Systemtexte auf Deutsch (deutsche Lokalisierung im App-Bundle deklariert).
- „Feedback senden …“ größer über dem Hinweis unten links und im Hilfe-Menü.
- Ziel-Mac, Modell- und Baujahrfilter bleiben zwischen Starts erhalten.
- Build-Ausgaben liegen in `dist/`; nur die drei neuesten Versionen bleiben erhalten.

Universal ab macOS 13, Build 23. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
