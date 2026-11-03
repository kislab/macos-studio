## macOS Studio 1.2.16 — USB-Erstellung über Terminal

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.16/macOS-Studio-1.2.16-Universal.dmg)**

**Fehler 250 behoben.** createinstallmedia scheiterte beim Schreiben von `.IAPhysicalMedia` mit „Operation not permitted“, obwohl macOS Studio Festplattenvollzugriff hatte. Laut Systemprotokoll ordnet macOS den Vorgang bei AppleScript-Administratorrechten dem Systemdienst `authtrampoline` zu, nicht der App. Für diesen Dienst kann macOS keine Freigabe abfragen und verweigert den Zugriff.

Ab 1.2.16 öffnet macOS Studio nach der Bestätigung ein Terminal-Fenster. Dort wird das Mac-Passwort für `sudo` eingegeben; der Fortschritt von createinstallmedia erscheint live. Die Sicherheitsprüfungen (Volume-UUID, extern, Mountpoint, APFS-Vorbereitung) laufen unverändert direkt vor dem Schreiben. Das Ergebnis und das Protokoll übernimmt die App nach Abschluss. Mit „Warten beenden“ lässt sich das Warten in der App beenden.

Terminal benötigt einmalig Zugriff auf Wechselmedien (macOS fragt) oder Festplattenvollzugriff. Diese Freigabe bleibt bei App-Updates erhalten.

Enthält den automatischen Neustart nach Updates aus 1.2.15. Universal ab macOS 13, Build 19. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
