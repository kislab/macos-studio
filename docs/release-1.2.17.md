## macOS Studio 1.2.17 — Fehlerbehebungen

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.17/macOS-Studio-1.2.17-Universal.dmg)**

- **Installer löschen:** Von `softwareupdate` geladene Installer gehören `root`. Das bisherige Verschieben nach `~/.Trash` mit AppleScript-Administratorrechten wäre am macOS-Datenschutz gescheitert, da der Papierkorb geschützt ist und macOS den Vorgang dem Systemdienst `authtrampoline` zuordnet. Jetzt überträgt die Administratorfreigabe nur den Besitz des bestätigten, erneut geprüften Installers an den Nutzer. Anschließend verschiebt die App ihn wie gewohnt wiederherstellbar in den Papierkorb.
- **Version eingeben:** Manuell angeforderte Versionen tragen den Titel „macOS“ und passten dadurch auf jeden vorhandenen Installer. Der Download wurde deshalb immer abgelehnt, sobald irgendein Installer vorhanden war. Behoben; nach dem Download wird der geänderte Installer erkannt.
- **USB erstellen:** Nach „Warten beenden“ löscht die App die Auftragsdaten nicht mehr, während Terminal noch schreibt.

Universal ab macOS 13, Build 20. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
