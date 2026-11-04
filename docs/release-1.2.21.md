## macOS Studio 1.2.21 — Installer für andere Macs und Löschen repariert

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.21/macOS-Studio-1.2.21-Universal.dmg)**

**Installer für andere Macs**
- Bisher zeigte die App nur, was `softwareupdate` für den eigenen Mac anbietet. Auf Intel-Macs fehlten dadurch macOS 27 „Golden Gate“ und meist auch macOS 26 „Tahoe“.
- Jetzt liest die App zusätzlich Apples öffentlichen Software-Katalog und listet alle vollständigen Installer (ab macOS 11). Versionen, die der eigene Mac nicht installieren kann, sind markiert („für andere Macs als Apple-Paket“).
- Für diese Einträge lädt die App `InstallAssistant.pkg` direkt von Apple, prüft Größe und Apple-Signatur (`pkgutil --check-signature`) und lässt Apples `installer` daraus „Installiere macOS ….app“ in /Programme erstellen. Dafür fragt macOS nach dem Administratorpasswort. Das installiert **nicht** macOS auf dem Mac.
- Versionen, die `softwareupdate` anbietet, laden weiterhin wie bisher.

**Installer lokal löschen**
- Von Apple geladene, root-eigene Installer in /Programme ließen sich nicht entfernen: macOS' Schutz „App-Verwaltung“ blockierte selbst mit Administratorrechten (`Operation not permitted`).
- Der Finder legt den Installer jetzt wiederherstellbar in den Papierkorb und fragt dabei selbst nach dem Passwort. Beim ersten Mal fragt macOS, ob macOS Studio den Finder steuern darf.
- Klappt das nicht, markiert die App den Installer im Finder (einfach in den Papierkorb ziehen) und bietet die passende Datenschutzeinstellung an.

Universal ab macOS 13, Build 24. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
