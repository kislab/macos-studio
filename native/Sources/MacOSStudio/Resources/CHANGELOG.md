Version 1.8.2

• Updates: Neuer Signaturschlüssel für automatische Updates. Ab dieser Version kommen Updates wieder automatisch. Wer 1.8.1 oder älter nutzt, installiert 1.8.2 einmal von Hand aus der DMG.

Version 1.8.1

• USB-Stick: Wird das Terminal-Fenster geschlossen, bevor der Vorgang fertig ist, merkt die App das jetzt sofort und meldet, ob der USB-Stick unverändert oder möglicherweise unvollständig ist. Bisher wartete sie ohne Ende und blockierte weitere Vorgänge und Updates.

• Downloads fortsetzen: Beim Anhalten eines Apple-Pakets gingen die Daten zum Fortsetzen auf langsamen Macs gelegentlich verloren, sodass der Download von vorn begann. Die App wartet jetzt zuverlässig, bis sie gesichert sind.

• Speicherplatz: Die Prüfung vor dem Download berücksichtigt jetzt auch den Zwischenspeicher für Apple-Pakete und blockiert nicht mehr, wenn macOS den freien Platz nicht meldet.

• Schnellere Protokollanzeige bei langen Downloads und Wiederherstellungen.

Version 1.8.0

• Neue Geräte automatisch: Einmal täglich gleicht OS Studio Apples Geräte- und macOS-Listen mit der eingebauten Datenbank ab. Erscheint ein neues iPhone, iPad oder ein neuer Mac, holt die App Name und Daten von AppleDB – ohne App-Update. Neue Macs erscheinen sofort unter „Mac suchen“, neue iPhones und iPads mit Namen im Reiter „Gerät“. „Meinen Mac erkennen“ schlägt einen noch unbekannten Mac direkt nach.

• Einstellungen → Neue Geräte: abschaltbar, mit „Jetzt prüfen“ und einer Liste der automatisch erkannten Geräte. An AppleDB gehen nur Modellkennungen unbekannter Geräte, keine Daten über diesen Mac.

• Englisch: Abschnittstitel der Einstellungen, Statusabzeichen und einige Statusmeldungen waren noch deutsch.

Version 1.7.1

• Neue Geräte: iPad mini (A20 Pro), MacBook Pro 14" und 16" mit M5 Pro / M5 Max und PROLED-XDR-Display, MacBook Pro 14" (M6) und iMac 24" (M6) – alle vom November 2026. Damit kennt die App jedes iPhone und iPad aus Apples aktueller Firmwareliste und jeden Mac aus Apples macOS-Liste.

Version 1.7.0

• Englisch: Ist macOS auf Englisch eingestellt, erscheint OS Studio jetzt auf Englisch – Menüs, Hinweise, Fehlermeldungen und Anleitungen. Auf Deutsch bleibt alles wie gewohnt. Die Sprache lässt sich pro App unter Systemeinstellungen → Allgemein → Sprache & Region wählen.

• Downloads fortsetzen: Bricht der Download eines Apple-Pakets ab (Verbindung weg, abgebrochen, App beendet), lädt „Fortsetzen“ ab der Abbruchstelle weiter statt von vorn. Fertig geladene Teile bleiben erhalten; „Verwerfen“ löscht sie.

• Behoben: „Fortsetzen“ bei IPSW-Firmware schlug fehl, weil Apples Antwort auf eine Fortsetzung (HTTP 206) als Fehler galt.

• Noch ältere Installer: OS X Yosemite, El Capitan und macOS Sierra (10.10–10.12) lassen sich von Apple laden. Das Abbild wird geprüft, die Paketsignatur kontrolliert und die Installer-App ohne Administratorpasswort zusammengesetzt. Beim USB-Stick übergibt die App diesen Versionen automatisch den Installer-Pfad, den ihr createinstallmedia verlangt.

• Wichtig für Macs mit Apple-Chip: macOS startet dort das ältere createinstallmedia von OS X 10.10 bis macOS 10.15 nicht mehr – auch nicht mit Rosetta (der Hinweis auf Rosetta aus 1.6.0 war falsch). Laden geht weiterhin; den USB-Stick mit der fertigen Installer-App an einem Intel-Mac erstellen. Die App prüft das vor dem Löschen und lässt den Stick unverändert.

• Flashen: Wird Apples Firmwareliste gerade geladen, wartet die Prüfsummen-Kontrolle jetzt darauf, statt die Prüfung auszulassen.

Version 1.6.0

• Ältere Installer: macOS High Sierra, Mojave und Catalina (10.13–10.15) lassen sich jetzt direkt aus Apples Katalog laden – auch auf Macs, denen Apple diese Versionen nicht mehr anbietet. Die App lädt die Installationsdateien, prüft jede gegen Apples Prüfsumme und setzt daraus „macOS … installieren.app“ zusammen. Ein Administratorpasswort ist dafür nicht nötig.

• Prüfsummen bei Apple-Paketen: Auch InstallAssistant.pkg (macOS 11 und neuer) wird nach dem Download Block für Block mit Apples SHA-256-Prüfdaten verglichen.

• Flashen nur mit intakter Firmware: Vor dem Flashen vergleicht die App die IPSW-Datei mit Apples SHA-1-Prüfsumme – auch bei selbst gewählten Dateien und älteren Versionen. Stimmt sie nicht, wird das Gerät nicht angefasst. Bereits geprüfte, unveränderte Dateien werden nicht erneut gerechnet.

• USB-Stick: Ältere Installer enthalten nur ein Intel-Programm. Fehlt auf einem Mac mit Apple-Chip Rosetta, sagt die App das vor dem Löschen des Sticks.

Version 1.5.5

• Ein iPhone/iPad im Restore-System (während des Flashens oder nach einem Abbruch) wurde fälschlich als „gesperrt“ angezeigt. Jetzt steht es als „Gerät im Restore-System“ mit Knopf „Zum Gerät …“ da.

• „Wiederherstellungsmodus per Anstecken“ blieb auf „wird versetzt …“ hängen, wenn das Gerät während des Auslesens abgezogen wurde.

• Nach dem Flashen wird die Geräteliste sofort aktualisiert.

Version 1.5.4

• Flashen über Dock oder Hub: Die App wartet jetzt bis zu drei Minuten, bis sich das Gerät nach jedem Neustart wieder meldet. Bricht die Verbindung ab, versucht sie es automatisch bis zu dreimal. Der Mac bleibt währenddessen wach.

• Verständliche Fehler: Statt nur „Operation restore failed“ zeigt die App die letzten Meldungen von Apple Configurator und erklärt bekannte Fehlercodes (z. B. 4013 = Verbindung abgerissen, 3194 = Apple-Freigabe fehlt). Das vollständige Protokoll liegt unter ~/Library/Logs/OS Studio („Protokoll anzeigen“).

• Gerät: Hängt ein iPhone/iPad nach einem Abbruch im Restore-System fest, steht das jetzt mit Hinweis dabei. Geräte am Dock/Hub werden erkannt und gekennzeichnet.

Version 1.5.3

• Flashen: Der Fortschrittsbalken zeigt jetzt den Gesamtfortschritt über alle Schritte. Vorher sprang er auf die Prozente des aktuellen Schritts (z. B. sofort 49 %). Darunter steht „Schritt 3 von 7 · Name · 49 % dieses Schritts“.

• Speicherort der IPSW: Im Reiter „Gerät“ und während des Flashens steht der vollständige Pfad der verwendeten Firmware-Datei – mit „Im Finder zeigen“. Noch nicht geladene Firmware zeigt, wohin sie gespeichert wird.

Version 1.5.2

• Gerät: Flashen startet nie mehr von selbst. Zuerst „Firmware laden“ (lädt und prüft nur – am Gerät ändert sich nichts), danach erscheint „Flashen …“, das man selbst drücken und bestätigen muss. Das gilt auch, wenn ein Gerät im DFU-Modus erkannt wird.

Version 1.5.1

• Firmware-Download: Während des Ladens steht jetzt „IPSW wird geladen …“ statt dauerhaft „Speicherplatz wird geprüft …“.

Version 1.5.0

• iPhone & iPad: Neuer Reiter „Gerät“ (jetzt der erste). Ein angestecktes iPhone oder iPad wird sofort erkannt – auch im DFU- und im Wiederherstellungsmodus – mit Modell, Foto und Modus.

• Die App zeigt direkt die neueste von Apple freigegebene Firmware für genau dieses Modell. „Laden & flashen“ lädt sie, prüft die Prüfsumme und flasht danach automatisch – in einem Schritt. Ist sie schon geladen, startet das Flashen sofort.

• „Reparieren“ (Daten bleiben) ist in den neuen Reiter gewandert. Eine bestimmte Version wählt man über „Andere Version …“ im Flasher.

• Extras: Ist ein Gerät im DFU- oder Wiederherstellungsmodus, führt „Flashen …“ direkt dorthin.

Version 1.4.0

• iPhone & iPad: Neuer Reiter „Wiederherstellen“ – wie in Apple Configurator. Geräte im Wiederherstellungs- oder DFU-Modus erscheinen mit ihrem Modus in einer Liste.

• „Reparieren“ installiert das System neu, Fotos, Apps und Daten bleiben erhalten. Laut Apple der erste Schritt für Geräte, die im Wiederherstellungsmodus hängen.

• „Wiederherstellen“ lädt die neueste von Apple freigegebene iOS- bzw. iPadOS-Version automatisch und installiert sie – dabei werden alle Daten gelöscht. Eine IPSW-Datei ist dafür nicht nötig.

• „Wiederherstellungsmodus per Anstecken“ ist direkt im neuen Reiter verfügbar: Gerät anstecken, reparieren oder wiederherstellen – ohne Tasten.

Version 1.3.3

• Wiederherstellungsmodus per Anstecken bei gesperrten Geräten: Lehnt ein gesperrtes oder noch nicht vertrautes iPhone/iPad ab, versucht die App es jetzt automatisch alle paar Sekunden erneut – sobald das Gerät entsperrt bzw. „Vertrauen“ getippt ist, geht es durch. Kein Abziehen und neu Anstecken mehr nötig.

• Gesperrte Geräte, die per USB keine Daten freigeben (iOS-Schutz nach längerer Sperre), werden jetzt als „Gesperrt“ angezeigt statt „Kein Gerät angeschlossen“ – mit Hinweis, was zu tun ist.

• Neu: Anleitung, um ein Gerät per Tasten in den Wiederherstellungsmodus zu bringen – funktioniert auch gesperrt und ohne Code.

• Der Befehl wird erst gesendet, wenn die App das Gerät fertig ausgelesen hat; die Oberfläche bleibt dabei bedienbar.

Version 1.3.2

• USB-Erstellung: Wird das Terminal-Fenster nach „Abbrechen“ geschlossen, hängt die App nicht mehr endlos, sondern meldet den Abbruch nach spätestens einer Minute.

• iPhone & iPad: Lässt sich ein abgebrochener Download nicht mehr fortsetzen, startet „Laden“ beim nächsten Mal neu, statt immer wieder zu scheitern.

• Der „Abbrechen“-Knopf im Fortschrittsbereich erscheint nur noch, wenn er tatsächlich etwas abbricht.

• Letzte Ausgabezeilen von Apple-Werkzeugen (z. B. Fehlermeldungen) gehen nicht mehr verloren; robusteres Lesen des Apple-Katalogs.

Version 1.3.1

• Wiederherstellungsmodus per Anstecken: Auf „Aktivieren“ klicken – die App zeigt „Stecke jetzt ein iPhone oder iPad an …“. Jedes dann angesteckte Gerät wird ohne Tastendrücken in den Wiederherstellungsmodus versetzt. Das klappt meist auch ohne Entsperren. Zu finden im Flasher und in den Extras.

• Extras aufgeräumt: Reiter „iPhone & iPad“ und „Mac (USB-C)“. Alle angeschlossenen Geräte stehen in einer Liste mit ihrem Modus (Normal, Wiederherstellung, DFU) und der passenden Aktion. „Per Tasten neu starten“ ist jetzt zum Aufklappen.

Version 1.3.0

• iPhone & iPad: Neuer „Flasher“. Unter „iPhone & iPad“ lässt sich jetzt zwischen „Firmware laden“ und „Flasher“ wechseln. Der Flasher installiert eine IPSW-Datei auf ein per USB verbundenes iPhone oder iPad – im normalen, im Wiederherstellungs- oder im DFU-Modus.

• Flasher: Die App liest Version und unterstützte Modelle direkt aus der IPSW und lässt nur passende Dateien zu. Bereits geladene, passende Firmware wird per Klick vorgeschlagen.

• Flasher: Vor dem Flashen fragt die App ausdrücklich nach, da alle Daten auf dem Gerät gelöscht werden. Fortschritt erscheint im Fenster und am Dock-Symbol.

• Der Flasher nutzt Apples kostenloses „Apple Configurator“ (cfgutil). Fehlt es, bietet die App den Link zum App Store an.

Version 1.2.0

• iPhone & iPad: „Prüfen“ gleicht eine geladene Firmware mit Apples SHA-1-Prüfsumme ab und markiert beschädigte oder unvollständige Dateien.

• iPhone & iPad: Abgebrochene oder fehlgeschlagene Downloads lassen sich fortsetzen, statt die ganze Datei neu zu laden.

• iPhone & iPad: Vor dem Laden prüft die App, ob genug Speicherplatz frei ist, und warnt rechtzeitig.

• iPhone & iPad: „Aufräumen“ schlägt ältere IPSW-Dateien im Ordner zum Verschieben in den Papierkorb vor.

• Installer lokal: „Prüfen“ kontrolliert, ob die Installationsdaten vollständig sind.

• Laufende Downloads und die USB-Erstellung zeigen den Fortschritt jetzt auch als Prozentzahl am Dock-Symbol.

• Hilfe und Einstellungen: „Diagnose exportieren …“ sichert App-Infos und das letzte Protokoll als Textdatei für Fehlerberichte.

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
