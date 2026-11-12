## OS Studio 1.8.1 — Fehlerbehebungen

**[App herunterladen (DMG)](https://github.com/kislab/macos-studio/releases/download/v1.8.1/OS-Studio-1.8.1-Universal.dmg)**

- **USB-Stick:** Wird das Terminal-Fenster vor dem Ende geschlossen (auch während der Passwortabfrage), erkennt die App das sofort und meldet, ob der USB-Stick unverändert oder möglicherweise unvollständig ist – statt endlos zu warten und weitere Vorgänge und Updates zu blockieren. Der Arbeitsordner des Root-Befehls wird immer frisch angelegt und nie wiederverwendet.
- **Downloads fortsetzen:** Beim Anhalten eines Apple-Pakets wartet die App jetzt auf Apples Fortsetzungsdaten, statt nach einer festen halben Sekunde aufzugeben. Dadurch beginnt ein angehaltener Download nicht mehr von vorn.
- **Speicherplatz:** Vor dem Download werden /Applications und der Zwischenspeicher für Apple-Pakete geprüft; ist der freie Platz nicht ermittelbar, blockiert die App nicht mehr.
- **Leistung:** Lange Protokolle (softwareupdate, cfgutil) werden ohne ständiges Durchzählen gekürzt.
- **Projekt:** Neuer GitHub-Workflow baut und prüft jeden Push (`swift run StudioChecks`, Übersetzungen). Die Release-Bereinigung behält immer das Release, auf das `appcast.xml` zeigt.

Universal für Intel und Apple Silicon, ab macOS 13. Build 51. Ed25519-signierte Updates; App ad-hoc signiert, nicht notarisiert.
