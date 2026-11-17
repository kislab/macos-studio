import Foundation

/// Mac maintenance tools under Extras: repair LaunchServices/Spotlight, delete a computer's old Time Machine backups.
/// Both run as root commands in Terminal (see TerminalJob); progress is reported with marker lines.
public enum SpotlightRepair {
    public static let stepMarker = "REPAIR-STEP"
    public static let doneMarker = "REPAIR-DONE"
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Root command. LaunchServices and the UI processes belong to the user who started sudo ($SUDO_USER);
    /// only the Spotlight index reset needs root.
    public static func rootCommand(cancelFile: URL) -> String {
        [
            "if [ -e " + shellQuote(cancelFile.path) + " ]; then echo 'Abgebrochen. Es wurde nichts geändert.'; exit 130; fi",
            "user=\"${SUDO_USER:-$(/usr/bin/stat -f %Su /dev/console)}\"",
            "if [ -z \"$user\" ] || [ \"$user\" = root ]; then echo 'Benutzer nicht ermittelbar. Abbruch ohne Änderung.'; exit 3; fi",
            "echo '\(stepMarker) 1 3'",
            "/usr/bin/sudo -u \"$user\" " + shellQuote(lsregister) + " -delete -r -domain local -domain system -domain user",
            "echo '\(stepMarker) 2 3'",
            "/usr/bin/mdutil -E /",
            "echo '\(stepMarker) 3 3'",
            "/usr/bin/killall -u \"$user\" Dock Finder SystemUIServer 2>/dev/null",
            "echo '\(doneMarker)'"
        ].joined(separator: "\n")
    }

    /// Current step (1–3) from the output, nil before the first one.
    public static func step(in output: String) -> Int? {
        output.split(whereSeparator: \.isNewline).reversed().lazy.compactMap { line -> Int? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.count == 3, parts[0] == Substring(stepMarker) else { return nil }
            return Int(parts[1])
        }.first
    }
}

/// Time Machine backups on HFS+ drives (folder Backups.backupdb, one folder per computer).
public enum TimeMachineBackups {
    public static let folderName = "Backups.backupdb"
    public static let totalMarker = "TM-TOTAL"
    public static let stepMarker = "TM-STEP"
    public static let cleanupMarker = "TM-CLEANUP"
    public static let doneMarker = "TM-DONE"
    public static let cancelMarker = "TM-CANCEL"
    public static let noAccessMarker = "TM-NOACCESS"
    public static let missingExit: Int32 = 3
    public static let leftoverExit: Int32 = 5

    public struct Machine: Identifiable, Equatable, Sendable {
        public var id: String { name }
        public let name: String
        public let backups: Int
        public init(name: String, backups: Int) { self.name = name; self.backups = backups }
    }

    /// Backups.backupdb folders on all mounted volumes.
    public static func databases(volumes: [URL]? = nil) -> [URL] {
        let mounted = volumes ?? FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return mounted.map { $0.appendingPathComponent(folderName, isDirectory: true) }
            .filter { var dir: ObjCBool = false; return FileManager.default.fileExists(atPath: $0.path, isDirectory: &dir) && dir.boolValue }
            .sorted { $0.path < $1.path }
    }

    /// Computer folders with their number of backups ("Latest" is a link, not a backup). Throws when macOS denies access.
    public static func machines(in database: URL) throws -> [Machine] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(atPath: database.path).filter { valid($0) }.sorted().compactMap { name in
            let path = database.appendingPathComponent(name).path
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &dir), dir.boolValue,
                  (try? fm.destinationOfSymbolicLink(atPath: path)) == nil else { return nil }
            let snapshots = (try? fm.contentsOfDirectory(atPath: path)) ?? []
            return Machine(name: name, backups: snapshots.filter { $0 != "Latest" && !$0.hasPrefix(".") }.count)
        }
    }

    /// A plain folder name: no path separators, not hidden, not "." or "..".
    public static func valid(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && name.count <= 255
            && name.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// True for "Operation not permitted"/"Permission denied" from the file system.
    public static func isAccessDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return true }
        let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError) ?? ns
        return underlying.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(underlying.code)
    }

    /// Root command: deletes one computer's backups one by one with `tmutil delete` (falls back to rm),
    /// then the computer folder. Stops between backups when `cancelFile` exists.
    public static func deleteCommand(database: URL, machine: String, cancelFile: URL) -> String? {
        guard valid(machine) else { return nil }
        let target = shellQuote(database.appendingPathComponent(machine).path)
        let cancel = shellQuote(cancelFile.path)
        return [
            "T=" + target,
            "if [ ! -d \"$T\" ] || [ -L \"$T\" ]; then echo 'Der Rechner-Ordner wurde nicht gefunden. Abbruch ohne Änderung.'; exit \(missingExit); fi",
            "if ! /bin/ls \"$T\" >/dev/null 2>&1; then echo '\(noAccessMarker)'; exit 77; fi",
            "cd \"$T\" || exit \(missingExit)",
            "total=0; for s in *; do [ \"$s\" = Latest ] && continue; [ -e \"$s\" ] && total=$((total+1)); done",
            "echo \"\(totalMarker) $total\"",
            "i=0",
            "for s in *; do",
            "  [ \"$s\" = Latest ] && continue",
            "  [ -e \"$s\" ] || continue",
            "  if [ -e " + cancel + " ]; then echo '\(cancelMarker)'; exit 130; fi",
            "  i=$((i+1)); echo \"\(stepMarker) $i $total $s\"",
            "  /usr/bin/tmutil delete -p \"$T/$s\" >/dev/null 2>&1 || /bin/rm -rf \"$T/$s\"",
            "done",
            "if [ -e " + cancel + " ]; then echo '\(cancelMarker)'; exit 130; fi",
            "echo '\(cleanupMarker)'",
            "cd / && /bin/rm -rf \"$T\" 2>/dev/null",
            "if [ -e \"$T\" ]; then echo 'Ein Rest des Rechner-Ordners konnte nicht entfernt werden.'; exit \(leftoverExit); fi",
            "echo '\(doneMarker)'"
        ].joined(separator: "\n")
    }

    public struct Progress: Equatable, Sendable {
        public var done: Int
        public var total: Int
        public var current: String?
        public var cleaningUp: Bool
        public var finished: Bool
        public var noAccess: Bool
        public var fraction: Double? { total > 0 ? min(1, Double(finished ? total : max(done - 1, 0)) / Double(total)) : (finished ? 1 : nil) }
    }

    public static func progress(in output: String) -> Progress {
        var result = Progress(done: 0, total: 0, current: nil, cleaningUp: false, finished: false, noAccess: false)
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: " ", maxSplits: 3)
            if parts.first == Substring(totalMarker), parts.count == 2, let total = Int(parts[1]) { result.total = total }
            else if parts.first == Substring(stepMarker), parts.count >= 3, let i = Int(parts[1]), let total = Int(parts[2]) {
                result.done = i; result.total = total; result.current = parts.count == 4 ? String(parts[3]) : nil
            }
            else if line == cleanupMarker { result.cleaningUp = true }
            else if line == doneMarker { result.finished = true; result.cleaningUp = false }
            else if line == noAccessMarker { result.noAccess = true }
        }
        return result
    }
}

/// Standalone shell scripts of the MacTweaks tools, for exporting and running without the app.
public enum MacTweaksScripts {
    public static let spotlightFileName = "Spotlight reparieren.sh"
    public static let timeMachineFileName = "Time-Machine-Backups löschen.sh"

    public static let spotlight = #"""
    #!/bin/bash
    # Spotlight & LaunchServices reparieren – exportiert aus OS Studio (MacTweaks).
    # Baut die LaunchServices-Datenbank neu auf, setzt den Spotlight-Index zurück und startet Dock, Finder und Menüleiste neu.
    # Nutzung: im Terminal ausführen; für den Spotlight-Schritt wird das Mac-Passwort abgefragt (sudo). Danach den Mac neu starten.

    echo "-----------------------------------------------------"
    echo "   Spotlight & LaunchServices reparieren"
    echo "-----------------------------------------------------"

    echo "[1/3] LaunchServices-Datenbank wird neu aufgebaut ..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -delete -r -domain local -domain system -domain user

    echo "[2/3] Spotlight-Index wird zurückgesetzt (Passwort nötig) ..."
    sudo /usr/bin/mdutil -E / || { echo "Spotlight-Index konnte nicht zurückgesetzt werden."; exit 1; }

    echo "[3/3] Dock, Finder und Menüleiste werden neu gestartet ..."
    /usr/bin/killall Dock Finder SystemUIServer 2>/dev/null

    echo "-----------------------------------------------------"
    echo "REPARATUR ABGESCHLOSSEN."
    echo "Bitte den Mac jetzt neu starten, damit alles vollständig wirkt."
    echo "-----------------------------------------------------"

    """#

    public static let timeMachine = #"""
    #!/bin/zsh
    # Alte Time-Machine-Backups löschen – exportiert aus OS Studio (MacTweaks).
    # Löscht alle Backups eines Rechners aus Backups.backupdb (Time-Machine-Laufwerke im Format Mac OS Extended), mit Fortschritt.
    # Terminal braucht dafür „Festplattenvollzugriff“ (Systemeinstellungen › Datenschutz & Sicherheit).

    DBS=(/Volumes/*/Backups.backupdb(N/))
    if [[ ${#DBS[@]} -eq 0 ]]; then
      echo "Kein Time-Machine-Laufwerk mit Backups.backupdb angeschlossen."; exit 1
    fi
    if [[ ${#DBS[@]} -eq 1 ]]; then
      DB="${DBS[1]}"
    else
      echo "Time-Machine-Laufwerke:"
      for n in {1..${#DBS[@]}}; do printf "  %2d) %s\n" $n "${DBS[$n]:h:t}"; done
      read "?Welches Laufwerk? Nummer eingeben (Enter = abbrechen): " PICK
      if [[ -z "$PICK" || ! "$PICK" =~ '^[0-9]+$' || $PICK -lt 1 || $PICK -gt ${#DBS[@]} ]]; then echo "Abgebrochen."; exit 0; fi
      DB="${DBS[$PICK]}"
    fi
    VOL="${DB:h}"

    if ! ls "$DB" >/dev/null 2>&1; then
      echo "Kein Zugriff auf $DB:"
      ls "$DB" 2>&1 | head -3
      echo "Bitte Terminal unter Systemeinstellungen > Datenschutz & Sicherheit > Festplattenvollzugriff erlauben und Terminal neu starten."
      exit 1
    fi

    MACHINES=("${(@f)$(ls -1 "$DB")}")
    if [[ ${#MACHINES[@]} -eq 0 || -z "${MACHINES[1]}" ]]; then
      echo "Keine Rechner-Ordner in $DB gefunden."; exit 1
    fi

    echo "Rechner-Ordner auf ${VOL:t}:"
    for n in {1..${#MACHINES[@]}}; do
      cnt=$(ls -1 "$DB/${MACHINES[$n]}" 2>/dev/null | grep -vc '^Latest$')
      printf "  %2d) %s  (%s Backups)\n" $n "${MACHINES[$n]}" "$cnt"
    done
    echo
    read "?Welchen Rechner löschen? Nummer eingeben (Enter = abbrechen): " CHOICE
    if [[ -z "$CHOICE" || ! "$CHOICE" =~ '^[0-9]+$' || $CHOICE -lt 1 || $CHOICE -gt ${#MACHINES[@]} ]]; then
      echo "Abgebrochen."; exit 0
    fi
    MACHINE="${MACHINES[$CHOICE]}"
    TARGET="$DB/$MACHINE"

    SNAPS=("${(@f)$(ls -1 "$TARGET" | grep -v '^Latest$')}")
    TOTAL=${#SNAPS[@]}
    echo "Zu löschen: $TARGET  ($TOTAL Backups)"
    read "?ACHTUNG: Das ist endgültig und nicht rückgängig zu machen. Wirklich löschen? (ja/nein) " ANSWER
    [[ "$ANSWER" == "ja" ]] || { echo "Abgebrochen."; exit 0; }

    sudo -v || exit 1
    # sudo-Passwort während des Löschens gültig halten
    ( while true; do sudo -n true 2>/dev/null; sleep 50; done ) &
    KEEPALIVE=$!
    trap 'kill $KEEPALIVE 2>/dev/null' EXIT

    free_kb() { df -k "$VOL" | awk 'NR==2{print $4}'; }
    gb() { awk -v k="$1" 'BEGIN{printf "%.1f", k/1048576}'; }

    START_FREE=$(free_kb)
    echo "Frei vor dem Löschen: $(gb $START_FREE) GB"
    echo

    # Zeigt Balken + Live-Werte, solange PID $1 läuft
    show_progress() {
      local pid=$1 snap_start=$2 last=$(free_kb) last_t=$SECONDS rate="0.0"
      while kill -0 $pid 2>/dev/null; do
        local now=$(free_kb)
        local pct=$(( (i - 1) * 100 / TOTAL ))
        local filled=$(( pct / 2 ))
        local bar=$(printf '%*s' $filled '' | tr ' ' '#')$(printf '%*s' $((50-filled)) '' | tr ' ' '-')
        if (( SECONDS - last_t >= 2 )); then
          rate=$(awk -v d=$((now - last)) -v t=$((SECONDS - last_t)) 'BEGIN{v=d/1024/t; if(v<0)v=0; printf "%.1f", v}')
          last=$now; last_t=$SECONDS
        fi
        printf "\r[%s] %3d%%  (%d/%d) %s\n" "$bar" "$pct" "$i" "$TOTAL" "$s"
        printf "  dieses Backup: %6s GB | gesamt freigegeben: %6s GB | jetzt frei: %6s GB | %6s MB/s   \033[1A\r" \
          "$(gb $((now - snap_start)))" "$(gb $((now - START_FREE)))" "$(gb $now)" "$rate"
        sleep 1
      done
    }

    i=0
    for s in "${SNAPS[@]}"; do
      [[ -z "$s" ]] && continue
      i=$((i+1))
      SNAP_START=$(free_kb)
      sudo tmutil delete -p "$TARGET/$s" >/dev/null 2>&1 &
      PID=$!
      show_progress $PID $SNAP_START
      wait $PID || sudo rm -rf "$TARGET/$s"
    done
    END_FREE=$(free_kb)
    printf "\r[%s] 100%%  (%d/%d) fertig%*s\n" "$(printf '%*s' 50 '' | tr ' ' '#')" "$TOTAL" "$TOTAL" 30 ''
    printf "  gesamt freigegeben: %s GB | jetzt frei: %s GB%*s\n" "$(gb $((END_FREE - START_FREE)))" "$(gb $END_FREE)" 30 ''
    echo
    echo "Räume Restordner auf ..."
    sudo rm -rf "$TARGET" 2>/dev/null
    [[ -e "$TARGET" ]] && echo "Rest von $TARGET konnte nicht entfernt werden." || echo "Fertig: $MACHINE gelöscht."
    echo "Insgesamt freigegeben: $(gb $(( $(free_kb) - START_FREE ))) GB – jetzt frei: $(gb $(free_kb)) GB"

    """#
}
