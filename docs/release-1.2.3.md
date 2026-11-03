## macOS Studio 1.2.3 — Vorhandene Installer erkennen

**[App herunterladen und installieren (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.3/macOS-Studio-1.2.3-Universal.dmg)**

Die ZIP-Datei wird für automatische App-Updates benötigt. `SHA256SUMS.txt` enthält die Prüfsummen. Die Source-code-Archive sind für Entwickler.

Vor jedem Download sucht die App in Programme, Benutzer-Programme, Downloads, Schreibtisch und bereits ausgewählten Speicherorten nach macOS-Installern.

- Stimmen die auslesbare macOS-Version und der Build überein und sind Installationsdaten vorhanden, wird der lokale Installer für die USB-Erstellung ausgewählt. Ein erneuter Download entfällt.
- Unvollständige Installer werden vor dem Download mit Speicherort gemeldet.
- Bei einem gleichnamigen Installer ohne bestätigte Zielversion stoppt die App zur manuellen Prüfung, statt ihn als passenden Download zu behandeln.

Die Prüfung der Installationsdaten ist strukturell; Apples createinstallmedia bleibt die abschließende Integritätsprüfung. Diese Änderung repariert keine fehlenden Installationsdaten.

Universal für Intel und Apple Silicon ab macOS 13. Version 1.2.3, Build 6. ZIP und Update-Feed sind Ed25519-signiert. Die App ist ad-hoc signiert, nicht Apple-notarisiert.

Validierung: Universal-Build und alle neun Swift-Testgruppen erfolgreich, einschließlich Versions-/Build-Abgleich und Ablehnung unvollständiger Installer.
