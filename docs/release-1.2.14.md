## macOS Studio 1.2.14 — USB-Zugriff auf Wechselmedien

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.2.14/macOS-Studio-1.2.14-Universal.dmg)**

createinstallmedia scheiterte mit „Failed to write .IAPhysicalMedia cookie … Operation not permitted“ (250), weil macOS den Zugriff auf Wechselmedien verweigerte. Der App fehlte die Zugriffsbeschreibung, daher konnte macOS keine Abfrage anzeigen.

- Die App enthält jetzt `NSRemovableVolumesUsageDescription` und fragt den Zugriff auf Wechselmedien vor dem Löschen des USB-Sticks selbst ab.
- Wird der Zugriff verweigert, bricht die App vor jeder Änderung am Stick ab.
- Der Hinweis enthält einen Knopf „Datenschutzeinstellungen öffnen“.

Hinweis: Die App ist ad-hoc signiert. macOS bindet die Freigabe an die jeweilige Binärdatei, daher kann sie nach einem Update erneut abgefragt werden.

Universal ab macOS 13, Build 17. ZIP für Updates, SHA256SUMS.txt für Prüfsummen. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
