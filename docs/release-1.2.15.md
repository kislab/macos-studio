## macOS Studio 1.2.15 — Festplattenvollzugriff für USB und automatischer Neustart

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.15/macOS-Studio-1.2.15-Universal.dmg)**

**USB-Fehler 250 behoben:** createinstallmedia scheiterte beim Schreiben der Datei `.IAPhysicalMedia` mit „Operation not permitted“, obwohl der Zugriff auf Wechselmedien freigegeben war. Apples Werkzeug benötigt dafür Festplattenvollzugriff für die startende App. macOS Studio prüft das jetzt vor dem Löschen des Sticks und bietet einen Knopf zu „Datenschutz & Sicherheit → Festplattenvollzugriff“ an. Da die App ad-hoc signiert ist, muss der Eintrag nach einem Update eventuell entfernt und neu hinzugefügt werden.

**Automatischer Neustart:** Nach dem Laden und der Signaturprüfung eines Updates installiert sich macOS Studio automatisch und startet neu. Der zusätzliche Klick auf „Install and Relaunch“ entfällt.

Läuft gerade ein Installer-Download, eine USB-Erstellung, eine Suche oder ein Löschvorgang, wird nicht automatisch neu gestartet; dann erscheint wie bisher der Knopf zum Installieren.

Hinweis: Das automatische Neustarten wirkt ab Updates, die von 1.2.15 aus installiert werden. Das Update auf 1.2.15 selbst muss noch einmal bestätigt werden.

Enthält die Wechselmedien-Freigabe für USB aus 1.2.14. Universal ab macOS 13, Build 18. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
