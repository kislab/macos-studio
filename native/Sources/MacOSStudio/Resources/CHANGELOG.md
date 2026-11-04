Version 1.1.1

• Extras: Beim Anschließen eines iPhones/iPads bleibt die Oberfläche flüssig – das Auslesen (Verbinden, Kopplung, Sitzung) läuft jetzt im Hintergrund.

• iPhone & iPad: Der Ladebalken für die Gerätefotos zählt wieder korrekt und zeigt nur die tatsächlich geladenen Fotos.

• Intern: Geräte werden über Apples offizielle Retain/Release-Funktionen gehalten; Reste von Wiederherstellungs-Geräten werden sauber aufgeräumt.

Version 1.1

• iPhone & iPad: Die Gerätefotos werden jetzt mit sichtbarem Fortschritt geladen und auf dem Mac zwischengespeichert. Schon geladene Fotos werden nicht erneut geholt; beim nächsten Start sind sie sofort da.

• Extras: Neu „Mac in DFU versetzen (USB-C)“. Ein Apple-Silicon-Mac kann einen zweiten, über den DFU-Port verbundenen Mac per Klick in den DFU-Modus versetzen oder neu starten – ohne Tasten. Experimentell, mit Admin-Passwort. Für iPhone/iPad funktioniert das nicht.

Version 1.0

Erste offizielle Version von OS Studio. Die bisherigen Vorabversionen sind damit abgeschlossen.

OS Studio vereint:
• macOS-Installer von Apple laden – auch Versionen für andere Macs – und bootfähige USB-Sticks erstellen.
• Installer lokal verwalten und sicher in den Papierkorb legen.
• Mac anhand von Modell oder Seriennummer bestimmen.
• iPhone & iPad: aktuelle Firmware (IPSW) direkt von Apple laden, mit Gerätefotos und wählbarem Speicherort.
• Extras: Wiederherstellungsmodus per Klick, geführter DFU-Modus, Gerät aus dem Modus holen.
• Einstellungen und automatische, signierte Updates.

Version 1.2.28

• Extras: Neue Karte „Gerät aus dem Modus holen“. Hängt ein iPhone oder iPad im Wiederherstellungs- oder DFU-Modus, holt „Normal starten“ es per Klick wieder heraus. Zusätzlich gibt es für jedes Gerät die Tastenfolge, die immer funktioniert – auch im DFU-Modus und ohne „Vertrauen“.

Version 1.2.27

• Neu: Extras. iPhone oder iPad per Kabel anschließen – die App erkennt es und startet mit einem Klick den Wiederherstellungsmodus (Laptop und Kabel auf dem Display), ganz ohne Tasten. „Normal starten“ holt es wieder heraus. Dabei wird nichts gelöscht.

• Extras: DFU-Modus mit Anleitung. Den DFU-Modus lässt Apple nur über die Tasten am Gerät zu. Die App wählt die passende Tastenfolge für dein Modell, zählt die Sekunden mit und meldet, sobald das Gerät im DFU-Modus ist.

• Neu: Einstellungen (auch mit ⌘,). Automatische Update-Suche, Neuigkeiten nach Updates, Installer für andere Macs ein- oder ausblenden, Speicherort für iPhone-/iPad-Firmware, Gerätefotos laden und Zwischenspeicher leeren sowie alles auf Standard zurücksetzen.

Version 1.2.26

• iPhone & iPad: Jede Firmware zeigt jetzt das offizielle Foto des Geräts. Die App lädt die Fotos beim Start direkt von Apples Support-Seiten „iPhone-/iPad-Modell identifizieren“ und speichert sie auf deinem Mac zwischen – danach erscheinen sie auch ohne Internet. iPod touch behält sein Symbol.

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
