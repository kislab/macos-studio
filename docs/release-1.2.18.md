## macOS Studio 1.2.18 — USB-Fortschritt live in der App

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.18/macOS-Studio-1.2.18-Universal.dmg)**

Während der USB-Erstellung zeigt macOS Studio die Schritte jetzt live an, nicht erst nach Abschluss:

- Ziel-Laufwerk wird geprüft
- USB-Stick wird vorbereitet (APFS → Mac OS Extended, falls nötig)
- USB-Stick wird gelöscht · mit Prozent
- Installer wird auf den USB-Stick kopiert · mit Prozent
- USB-Stick wird bootfähig gemacht
- Fertig – USB-Stick ist bereit

Der Fortschrittsbalken übernimmt Apples Prozentangaben des jeweiligen Schritts; das Protokoll öffnet sich automatisch und läuft mit. Technisch läuft createinstallmedia im Terminal über `script`, das die Ausgabe ungepuffert in eine private Protokolldatei schreibt, die die App jede Sekunde liest.

Universal ab macOS 13, Build 21. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
