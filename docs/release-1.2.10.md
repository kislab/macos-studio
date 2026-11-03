## macOS Studio 1.2.10 — Aktuellen Update-Stand direkt abfragen

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.10/macOS-Studio-1.2.10-Universal.dmg)**

Start- und manuelle Update-Prüfungen ermitteln zuerst über die öffentliche GitHub-API den aktuellen Commit. Danach lädt Sparkle den signierten Feed genau dieses Commits, um veraltete Antworten der main-Adresse zu vermeiden. Die API-Abfrage hat ein Zeitlimit von zehn Sekunden. Ist die API nicht erreichbar oder limitiert, bleibt der signierte main-Feed als Rückfall erhalten. Signaturprüfungen bleiben verpflichtend.

Universal ab macOS 13, Build 13. ZIP für App-Updates, SHA256SUMS.txt für Prüfsummen. App ad-hoc signiert, nicht notarisiert.
