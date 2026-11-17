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
