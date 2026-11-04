Version 1.2.25

• iPhone & iPad: Die neuesten Geräte stehen jetzt oben (iPhone 18 Pro, iPhone 17, iPhone 16 …).

• iPhone & iPad: Neue Geräte haben jetzt ihren richtigen Namen: iPhone 18 Pro, iPhone 18 Pro Max, iPhone Duo, iPhone 17e, iPad Pro 11"/13" (M5) und iPad Air 11"/13" (M4).

Version 1.2.24

• iPhone & iPad: Jede Firmware hat jetzt ein eigenes Symbol – mit der passenden Bauform (Home-Taste, Notch oder Dynamic Island; iPad mit oder ohne Home-Taste) und der Systemversion.

• iPhone & iPad: Übersichtlich nach iPhone, iPad und iPod touch gruppiert und aufsteigend sortiert – iPhone 11, iPhone 12, iPhone 13 und so weiter.

• iPhone & iPad: Firmware (IPSW) landet weiterhin standardmäßig im Download-Ordner. Mit „Ändern …“ wählst du einen anderen Ordner, z. B. eine externe Festplatte; die Wahl bleibt gespeichert und gilt für iPhone, iPad und iPod touch. „Downloads verwenden“ stellt den Standard wieder her.

Version 1.2.23

• Neuer Name: Die App heißt jetzt „OS Studio“.

• Neu: iPhone & iPad. Lade die aktuelle Firmware (IPSW) für iPhone, iPad und iPod touch direkt von Apple. Die App nutzt dieselbe Liste wie der Finder, prüft jede Datei mit Apples Prüfsumme und legt sie in den Download-Ordner. Es wird nur geladen – kein Gerät wird verändert.

Version 1.2.22

• Mac suchen: Seriennummern werden jetzt direkt in der App erkannt – ohne dass sich eine Website öffnet, auch nicht mit Enter. Ältere Seriennummern (11–12 Zeichen, bis 2021) löst die App über Apples Modellabfrage auf und zeigt das passende Modell.

• Neuere Seriennummern (10 Zeichen, seit 2021) vergibt Apple zufällig; sie enthalten kein Modell. Die App erklärt das und nennt Alternativen: Modellnummer (z. B. A2337), Modellkennung oder „Meinen Mac erkennen“.

Version 1.2.21

• Installer für andere Macs: Die Liste zeigt jetzt alle vollständigen Installer aus Apples Katalog – auch Versionen, die dieser Mac selbst nicht installieren kann (z. B. macOS 27 oder 26 auf Intel-Macs). Solche Einträge sind markiert; die App lädt Apples Installationspaket, prüft Größe und Apple-Signatur und erstellt daraus die Installer-App für den USB-Stick (Administratorpasswort nötig).

• Installer lokal löschen: Von Apple geladene Installer ließen sich nicht entfernen („Operation not permitted“), weil macOS' App-Verwaltung Änderungen blockiert. Der Finder legt sie jetzt wiederherstellbar in den Papierkorb. Klappt das nicht, markiert die App den Installer im Finder und nennt die passende Datenschutzeinstellung.

Version 1.2.20

• Golden Gate: In der Mac-Suche fehlte macOS 27 „Golden Gate“ bei allen Macs. Mit gewähltem Ziel-Mac wurden macOS-27-Installer deshalb ausgeblendet. Alle Apple-Silicon-Macs unterstützen Golden Gate jetzt laut Apples Kompatibilitätsliste.

• Neue Macs in der Datenbank: MacBook Pro M5 (2025), MacBook Pro M5 Pro/Max, MacBook Air M5 und MacBook Neo (2026), Mac Studio 2025 und 2026 sowie Mac mini M6/M5 Pro (2026).

• USB erstellen: „Abbrechen“ beendet den Vorgang jetzt wirklich, auch im Terminal. Vor dem Löschen bleibt der Stick dabei unverändert.

• USB erstellen: Die App prüft vorher, ob der Stick groß genug ist, und testet noch vor dem Löschen, ob Terminal auf den Stick schreiben darf. Fehlt die Freigabe, bleibt der Stick unverändert.

• Update-Dialoge und Systemtexte erscheinen jetzt auf Deutsch.

• Feedback: Der Knopf „Feedback senden …“ steht größer über dem Hinweis unten links und zusätzlich im Hilfe-Menü.

• Mac-Suche: Ziel-Mac, Modell- und Baujahrfilter bleiben beim nächsten Start erhalten.

• Projekt: Build-Dateien liegen jetzt in dist/; es bleiben nur die drei neuesten Versionen.

Version 1.2.19

• Feedback: Unten links in der Seitenleiste öffnet „Feedback senden …“ dein E-Mail-Programm mit einer Nachricht an Kevin (mail@seitzke.com). App- und macOS-Version stehen bereits in der Nachricht.

Version 1.2.18

• USB erstellen: Schritte und Fortschritt erscheinen jetzt live auch in macOS Studio – Ziel prüfen, USB vorbereiten, Löschen, Kopieren und Bootfähig machen, jeweils mit Prozentangabe von Apple. Das Protokoll öffnet sich automatisch und läuft mit.

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
