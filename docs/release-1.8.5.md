## OS Studio 1.8.5 — Mac-Wartung

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.8.5/OS-Studio-1.8.5-Universal.dmg)**

Neuer Bereich **Extras › Mac-Wartung**:

- **Spotlight & LaunchServices reparieren:** Baut die LaunchServices-Datenbank neu auf, setzt den Spotlight-Index zurück und startet Dock, Finder und Menüleiste neu. Hilft bei falschen „Öffnen mit“-Einträgen, fehlenden Symbolen oder wenn Spotlight nichts findet.
- **Alte Time-Machine-Backups löschen:** Zeigt die Rechner auf einem Time-Machine-Laufwerk (Mac OS Extended, Ordner `Backups.backupdb`) mit der Zahl ihrer Backups. Ein ausgewählter Rechner wird nach Rückfrage gelöscht, mit Fortschritt und freigegebenem Speicher. Abbrechen ist zwischen zwei Backups möglich.

Beide Werkzeuge laufen mit Admin-Passwort im Terminal. Zum Auflisten und Löschen der Backups brauchen OS Studio bzw. Terminal den Festplattenvollzugriff.

Universal für Intel und Apple Silicon, ab macOS 13. Build 55.
