## macOS Studio 1.2.1 — Unvollständige Installer erkennen

Behebt eine fehlende Vorprüfung: Eine Installer-App konnte bisher bereits als USB-tauglich angezeigt werden, wenn nur `createinstallmedia` vorhanden war, selbst wenn die Installationsdaten fehlten. Apples Werkzeug lehnte sie dann mit Fehler 253 ab.

- Fehlende, leere oder nicht lesbare Installationsdateien in `Contents/SharedSupport` werden erkannt.
- Unter **Installer lokal** bleiben unvollständige Installer sichtbar, sind aber klar markiert; die USB-Aktion ist gesperrt.
- Für die USB-Auswahl und nach Downloads werden vorhandene Installationsdaten vorausgesetzt.
- Apples Meldung „does not appear to be a valid OS installer application“ erhält einen verständlichen Hinweis zum erneuten Laden.

Die Vorprüfung erkennt fehlende Daten, ist jedoch keine vollständige Integritätsprüfung des Apple-Installers. Bereits beschädigte Downloads werden nicht repariert oder automatisch gelöscht. Der macOS-Installer wird nicht automatisch geöffnet.

**Update:** Ab App-Version 1.2 über **macOS Studio → Nach Updates suchen …** direkt installieren. Für Erstinstallationen gibt es die Universal-DMG bzw. ZIP, ab macOS 13 für Intel und Apple Silicon.

Weiterhin lokal ad-hoc signiert und nicht Apple-notarisiert. Update-Paket und Feed sind mit Ed25519 signiert.
