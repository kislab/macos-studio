## macOS Studio 1.1

Native SwiftUI-App zum Laden von macOS-Installern, Verwalten lokaler Installer und Erstellen bootfähiger USB-Sticks.

### In dieser Version
- **Installer lokal:** Größe und Speicherort anzeigen, im Finder öffnen, für USB auswählen und nach Bestätigung in den Papierkorb verschieben.
- **Übersichtlicher Mac-Check:** Gerätebilder, Baujahr- und Modellfilter, automatische Erkennung und aufklappbare Details.
- **Installer-Symbole** passend zur macOS-Version.
- **GB-Anzeige ohne Mbit/s**, Fortschrittsbalken direkt aus Apples Angaben.
- **Universal-App** für Intel und Apple Silicon ab macOS 13 Ventura.

### Installation
Die unten angehängte **macOS-Studio-1.1-Universal.dmg** laden, öffnen und **macOS Studio** auf **Programme** ziehen. Eine vorhandene ältere Version vorher beenden und beim Kopieren ersetzen.

Die `.sha256`-Datei dient zur Integritätsprüfung. Die automatisch von GitHub angebotenen „Source code“-Archive sind Quellcode, nicht der Installer.

### Hinweise
Diese Version ist **ad-hoc signiert, nicht Developer-ID-signiert und nicht Apple-notarisiert**. macOS kann eine Sicherheitswarnung anzeigen.

Die GB-Anzeige ist eine Schätzung. Modelldaten sind lokal gespeichert. USB-Erstellung löscht nach Bestätigung das gewählte Ziel-Volume; währenddessen gibt es keine Live-Prozentanzeige und keinen Abbruchknopf.

Neun automatisierte Prüfgruppen erfolgreich. Oberfläche, Live-Katalog und USB-Erkennung geprüft. Ein vollständiger Installer-Download, echtes USB-Schreiben und Ausführung auf Intel-Hardware wurden für dieses Release nicht durchgetestet.
