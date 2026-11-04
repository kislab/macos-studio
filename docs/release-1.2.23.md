## OS Studio 1.2.23 — neuer Name und Firmware für iPhone & iPad

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.23/OS-Studio-1.2.23-Universal.dmg)**

**Neuer Name**
- Aus „macOS Studio“ wird **OS Studio**. Einstellungen, Updates und Schlüssel bleiben erhalten (gleiche App-Kennung). Release-Dateien heißen ab jetzt `OS-Studio-…`.

**iPhone & iPad**
- Neuer Bereich in der Seitenleiste: aktuelle Firmware (IPSW) für iPhone, iPad und iPod touch.
- Quelle ist Apples öffentliche Geräteliste (`s.mzstatic.com/version`), die auch der Finder zum Wiederherstellen nutzt. Die Dateien kommen direkt von `updates.cdn-apple.com`.
- Jeder Download wird mit Apples SHA-1-Prüfsumme kontrolliert und erst danach in den Download-Ordner gelegt. Stimmt sie nicht, wird die Datei verworfen.
- Suche nach Gerätename, Modellkennung (z. B. `iPhone16,1`) oder Version.
- Nur Download: Kein Gerät wird verändert. Apple listet pro Gerät nur die aktuelle Version; ältere Versionen sind dort nicht mehr verfügbar und werden meist nicht mehr signiert.

Universal ab macOS 13, Build 26. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
