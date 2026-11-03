## macOS Studio 1.2 — Updates direkt in der App

macOS Studio kann neue Versionen jetzt selbst laden und installieren. Eine Update-DMG muss dafür nicht mehr geöffnet werden.

- Automatische Prüfung alle sechs Stunden nach Sparkles Zeitplan.
- Menüpunkt **macOS Studio → Nach Updates suchen …**.
- Bei einer neuen Version erscheint ein Hinweis; nach Bestätigung übernimmt die App Download, Prüfung, Austausch und Neustart.
- Update-Archiv und Feed werden mit Ed25519 signiert und vor Verwendung geprüft.
- Während laufender Downloads, USB-Erstellung oder Löschvorgänge wird kein Update-Neustart ausgeführt.

Alle Funktionen aus Version 1.1 bleiben enthalten: Installer-Download mit GB-Anzeige, lokale Installer-Verwaltung mit Papierkorb, Mac-Check und USB-Erstellung.

### Installation / Umstieg von 1.1
Version 1.1 enthält noch keinen Updater. **Version 1.2 muss deshalb einmal normal installiert werden.** Danach werden zukünftige Updates direkt in der App angeboten.

Für die Erstinstallation die DMG laden und die App auf Programme ziehen. Alternativ die Universal-ZIP entpacken und die App nach Programme kopieren. Die ZIP ist zugleich das signierte Paket für den In-App-Updater. Die automatisch angebotenen „Source code“-Archive sind kein App-Installer.

Intel und Apple Silicon, ab macOS 13 Ventura. Weiterhin ad-hoc signiert, nicht Apple-notarisiert. Der private Update-Schlüssel bleibt im lokalen Schlüsselbund des Herausgebers.

Neue GitHub-Commits allein lösen kein Update aus: Ein signiertes Release samt aktualisiertem Appcast ist erforderlich. Anleitung: `docs/UPDATES.md`.
