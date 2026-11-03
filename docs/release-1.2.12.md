## macOS Studio 1.2.12 — APFS-USB automatisch vorbereiten

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.12/macOS-Studio-1.2.12-Universal.dmg)**

Vor createinstallmedia wird ein APFS-Ziel als Mac OS Extended (Journaled) vorbereitet. Die automatische Umwandlung ist auf einen Container mit genau einem Volume und einem externen USB-Physical-Store beschränkt. Andere Partitionen bleiben erhalten. UUID, Mountpunkt, USB-Anbindung und externe Lage werden geprüft; unter Administratorrechten werden die Container-Struktur und Identitäten nochmals geprüft. Container mit mehreren Volumes werden abgelehnt.

Die bestehende Löschbestätigung nennt die Formatierung. Alle Daten auf dem bestätigten Ziel gehen verloren. Universal ab macOS 13, Build 15. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. App ad-hoc signiert, nicht notarisiert.
