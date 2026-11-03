Version 1.2.17

• Installer löschen: Von Apple geladene Installer gehören dem System. Das Verschieben in den Papierkorb mit Administratorfreigabe scheiterte bisher am macOS-Datenschutz für den Papierkorb. Jetzt überträgt die Freigabe nur den Besitz des bestätigten Installers an dich; danach verschiebt die App ihn normal und wiederherstellbar in den Papierkorb.

• Version eingeben: Eine manuell angeforderte Version wurde blockiert, sobald irgendein Installer vorhanden war. Das ist behoben.

• USB erstellen: Nach „Warten beenden“ bleiben die Terminal-Daten erhalten, solange der Vorgang dort noch läuft.

Version 1.2.16

• USB erstellen über Terminal: Fehler 250 („.IAPhysicalMedia … Operation not permitted“) ist behoben. macOS ordnete den Schreibvorgang bisher dem Systemdienst authtrampoline zu, nicht macOS Studio, deshalb half keine Freigabe der App. Jetzt öffnet sich nach der Bestätigung Terminal: Dort das Mac-Passwort eingeben, der Fortschritt erscheint live. Terminal benötigt einmalig Zugriff auf Wechselmedien bzw. Festplattenvollzugriff; diese Freigabe bleibt auch nach App-Updates erhalten.

• Die Prüfung auf Festplattenvollzugriff für macOS Studio entfällt wieder, da sie für die USB-Erstellung nicht nötig ist.

Version 1.2.15

• USB erstellen: Apples createinstallmedia benötigt Festplattenvollzugriff für macOS Studio, sonst scheitert es mit Fehler 250 (.IAPhysicalMedia). Die App prüft das jetzt vor dem Löschen des USB-Sticks und öffnet auf Wunsch direkt die passende Einstellung. Nach einem Update muss der Eintrag eventuell entfernt und neu hinzugefügt werden.

• Updates: Nach dem Laden und Prüfen eines Updates installiert sich die App automatisch und startet neu. Der zusätzliche Klick auf „Install and Relaunch“ entfällt. Läuft gerade ein Download, eine USB-Erstellung oder ein Löschvorgang, wartet die App weiterhin auf deine Bestätigung.

Version 1.2.14

• USB-Zugriff: Die App fragt jetzt selbst nach dem macOS-Zugriff auf Wechselmedien, bevor der USB-Stick gelöscht wird. Ohne Freigabe bleibt der Stick unverändert.

• Bei verweigertem Zugriff öffnet ein Knopf direkt die passenden Datenschutzeinstellungen.

Version 1.2.13

• Änderungsprotokoll: Nach einer neuen Version erscheint diese Übersicht einmalig. Im Menü „macOS Studio → Änderungsprotokoll“ kannst du sie wieder öffnen.

• Seriennummern: Die Suche startet eine Sekunde nach der letzten Eingabe automatisch im gemeinsamen Suchfeld. Der zusätzliche Suchknopf entfällt. Jede Seriennummer öffnet Apples Abfrage; die Nummer wird zum Einfügen kopiert. Eine lokale Seriennummernzuordnung findet nicht mehr statt.

• Gemerkte Ordner: Ausgewählte Installer und Suchordner werden als Lesezeichen gespeichert und beim nächsten Start wiederhergestellt.

• Weniger Zugriffsabfragen: Downloads und Schreibtisch werden erst nach deiner Ordnerauswahl durchsucht. Die App greift dort nicht mehr automatisch bei jedem Start zu.

• USB vorbereiten: Ein APFS-Container mit genau einem Volume wird vor der USB-Erstellung automatisch als Mac OS Extended formatiert. Mehrere Volumes werden zum Schutz anderer Daten abgelehnt.

• Verständlicher Hinweis, wenn macOS den Schreibzugriff auf den USB-Stick verweigert.

macOS verwaltet die Datenschutzrechte. Nach einem Signaturwechsel oder beim Widerrufen einer Freigabe kann eine erneute Abfrage notwendig sein. Die App ist derzeit ad-hoc signiert.
