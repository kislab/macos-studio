# App-Updates veröffentlichen

Ab Version 1.2 verwendet OS Studio Sparkle 2.10.1. Ab Version 1.2.2 prüft die App direkt bei jedem Start im Hintergrund und anschließend alle sechs Stunden auf Updates, sofern automatische Prüfungen aktiviert sind. Ab 1.2.4 wartet die Startprüfung auf das Fenster und laufende Vorgänge; sie erfolgt im Hintergrund ohne „aktuell“-Dialog. „OS Studio → Nach Updates suchen …“ prüft ebenfalls sofort. Vor dem Download wird der Nutzer gefragt; danach lädt Sparkle die ZIP-Datei, prüft die Ed25519-Signatur und ersetzt die App. Ab 1.2.15 erfolgen Installation und Neustart danach automatisch ohne weiteren Klick, sofern kein Vorgang läuft. Es muss keine DMG geöffnet werden.

Die App sperrt Update-Prüfungen und Neustarts während laufender Downloads, USB-Erstellung, Lösch- oder Suchvorgänge. Signierte Updates und signierter Feed sind verpflichtend. Es wird kein Systemprofil übertragen. Die privaten Schlüssel werden nicht mit ausgeliefert.

## Einmaliger Umstieg

Version 1.1 hat noch keinen Updater. Nutzer müssen Version 1.2 einmal normal installieren. Danach funktionieren In-App-Updates für zukünftige Releases.

## Neue Version veröffentlichen

Ein neuer Commit auf GitHub allein ist **kein** App-Update. Benötigt werden eine gebaute App, eine signierte ZIP, ein veröffentlichtes Release und ein aktualisierter signierter Feed.

1. In `native/build-app.sh` die `CFBundleShortVersionString` erhöhen (z. B. `1.3`) und `CFBundleVersion` strikt erhöhen (z. B. `4`). DMG-Skript und Update-Vorbereitung lesen die Version aus der gebauten App; Ausgaben landen in `dist/`, wo nur die drei neuesten Versionen erhalten bleiben. `build-dmg.sh` erzeugt auch die gemeinsame `dist/SHA256SUMS.txt`.
2. `./native/check-strings.sh` ausführen: Neue oder geänderte Texte brauchen eine englische Übersetzung in `native/Localization/en.lproj/Localizable.strings` (Deutsch ist die Ausgangssprache, die deutschen Texte sind die Schlüssel). Dann `./native/build-app.sh` ausführen und die App prüfen.
3. `./native/prepare-update.sh` ausführen. Das erzeugt die ZIP, Prüfsumme und `appcast.xml`; Archiv und Feed werden signiert und lokal verifiziert.
4. Code und Release-Beschreibung committen/pushen, den neuen Feed zunächst noch zurückhalten.
5. Ein GitHub-Release mit passendem Tag (z. B. `v1.3.0`) erstellen und ZIP und DMG für Erstinstallationen anhängen. Die Prüfsummen beider Dateien in einer gemeinsamen `SHA256SUMS.txt` hochladen; keine separaten `.dmg.sha256`/`.zip.sha256`-Assets. Oben in der Release-Beschreibung einen direkten DMG-Download-Link ergänzen.
6. Release veröffentlichen und die Erreichbarkeit des ZIP-Downloads prüfen.
7. Erst jetzt `appcast.xml` committen und pushen. Bereits installierte Apps erhalten dadurch das neue Angebot.
8. Nur die drei neuesten veröffentlichten Releases behalten. Ältere Releases samt Assets entfernen; Git-Tags bleiben erhalten. Der Workflow `release-retention.yml` führt die Bereinigung bei jeder Veröffentlichung aus.

Vorhandene Update-Archive überschreibt das Vorbereitungsskript nicht. Eine veröffentlichte Version nicht nachträglich mit anderen Binärdateien ersetzen; stattdessen Versions- und Buildnummer erhöhen. Signierte `appcast.xml` nicht manuell ändern, ohne sie erneut zu signieren.

## Update-Schlüssel

Der private Ed25519-Schlüssel liegt im lokalen macOS-Login-Schlüsselbund unter dem Sparkle-Account `macos-studio-kislab`. Nur der öffentliche Schlüssel steht in der App. Ohne diesen privaten Schlüssel lassen sich für die ausgelieferten Apps keine gültigen neuen Updates erstellen.

Den Schlüsselbund sicher sichern. Beim Wechsel des Entwicklungs-Macs den Schlüssel nach Sparkles Anleitung sicher übertragen; private Schlüssel niemals ins Repository, in Release-Dateien oder in Logs kopieren. GitHub allein kann keine neuen Updates signieren.

## Signierung

Die Ed25519-Update-Signatur ist unabhängig von Apples Developer-ID-Signierung und Notarisierung. Diese Version ist weiterhin ad-hoc signiert. Sparkle ersetzt keine Apple-Notarisierung.

## Quellen und Lizenz

- [Sparkle-Dokumentation](https://sparkle-project.org/documentation/)
- [SwiftUI-Integration](https://sparkle-project.org/documentation/programmatic-setup/)
- [Sparkle-Lizenz](licenses/Sparkle.txt), auch im App-Bundle enthalten
