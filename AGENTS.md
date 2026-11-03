# Projektablauf

Der Nutzer möchte fertige Updates automatisch veröffentlicht haben: Nach erfolgreichen relevanten Tests und Universal-Build die Versions- und Buildnummer erhöhen und ein signiertes GitHub-Release veröffentlichen, ohne erneut nach Bestätigung zu fragen. Die Versionsnummer muss bereits vor dem Build erhöht sein. Keine Veröffentlichung bei fehlgeschlagenen Prüfungen.

Release-Ablauf und Schlüsselverwaltung: siehe docs/UPDATES.md. Zuerst Release-Dateien veröffentlichen, danach den signierten appcast.xml pushen. Private Schlüssel bleiben im lokalen Schlüsselbund. Vorhandene veröffentlichte Versionen nicht überschreiben. Nicht zugehörige unversionierte Assets nicht pauschal committen.

Nach jeder erfolgreichen Veröffentlichung nur die drei neuesten veröffentlichten GitHub-Releases behalten. Ältere Releases samt Assets entfernen; Git-Tags und Quellcodehistorie behalten. Die aktuelle im appcast.xml referenzierte Version muss erhalten bleiben.
