## macOS Studio 1.2.13 — Änderungsprotokoll und gemerkte Ordner

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.13/macOS-Studio-1.2.13-Universal.dmg)**

Nach einer neuen Version erscheint einmalig das Änderungsprotokoll, auch über das App-Menü erreichbar. Installer- und Ordnerauswahl werden als Bookmarks gespeichert und beim Start wiederhergestellt. Downloads und Schreibtisch werden erst nach einer bewussten Ordnerauswahl durchsucht. Damit entfallen automatische Zugriffe auf diese geschützten Ordner.

Die Seriennummernsuche startet eine Sekunde nach der letzten Eingabe automatisch; der zusätzliche Suchknopf entfällt. Jede Seriennummer öffnet automatisch Apples offizielle Website; die Nummer wird zum Einfügen kopiert. Die lokale Seriennummernzuordnung entfällt. Apples CAPTCHA oder weitere Interaktion kann die App nicht automatisch erledigen.

Die automatische APFS-USB-Vorbereitung aus 1.2.12 bleibt enthalten. Datenschutzfehler beim Schreiben auf USB werden verständlicher gemeldet.

Wichtig: Bookmarks ersetzen keine macOS-Datenschutzfreigabe. Bei ad-hoc signierten Updates können Systemrechte erneut abgefragt werden. Auf diesem Mac ist keine Developer-ID-Signatur verfügbar; die App kann sich diese Rechte nicht selbst erteilen. Der direkte USB-Test hat die APFS-Konvertierung erfolgreich abgeschlossen, createinstallmedia wurde anschließend von macOS beim Schreiben der .IAPhysicalMedia-Datei blockiert (250). Eine erfolgreiche USB-Erstellung wird deshalb noch nicht behauptet.

Universal ab macOS 13, Build 16. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
