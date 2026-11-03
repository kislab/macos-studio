import Foundation

/// Runs an elevated command in Terminal so that Terminal (not the system authtrampoline)
/// is the responsible process for macOS privacy control. createinstallmedia needs that
/// to write `.IAPhysicalMedia` on the freshly erased USB volume.
public struct TerminalJob {
    public let directory: URL
    public var script: URL { directory.appendingPathComponent("USB-Stick erstellen.command") }
    public var statusFile: URL { directory.appendingPathComponent("status") }
    public var logFile: URL { directory.appendingPathComponent("output.log") }

    public init(directory: URL) { self.directory = directory }

    /// zsh script: sudo runs the already safety-checked root command, output is mirrored into the log,
    /// and the exit status is written atomically for the app to pick up.
    public func scriptText(rootCommand: String, headline: String) -> String {
        let status = shellQuote(statusFile.path)
        return """
        #!/bin/zsh
        clear
        print -r -- \(shellQuote(headline))
        print -r -- 'Bitte dein Mac-Passwort eingeben. Die Eingabe bleibt unsichtbar.'
        print
        /usr/bin/sudo /bin/bash -c \(shellQuote(rootCommand)) 2>&1 | /usr/bin/tee \(shellQuote(logFile.path))
        code=${pipestatus[1]}
        print -r -- "$code" > \(shellQuote(statusFile.path + ".tmp")) && /bin/mv \(shellQuote(statusFile.path + ".tmp")) \(status)
        print
        if [[ $code -eq 0 ]]; then print 'Fertig. Du kannst dieses Fenster schließen.'; else print "Fehlgeschlagen (Code $code). Details stehen auch in macOS Studio."; fi
        """ + "\n"
    }

    /// Creates a private (0700) directory and a read/execute-only (0500) script.
    public func write(rootCommand: String, headline: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(scriptText(rootCommand: rootCommand, headline: headline).utf8).write(to: script, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: script.path)
    }

    /// Exit status once Terminal has finished, otherwise nil.
    public func exitStatus() -> Int32? {
        guard let text = try? String(contentsOf: statusFile, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    public func output() -> String { (try? String(contentsOf: logFile, encoding: .utf8)) ?? "" }
    public func remove() { try? FileManager.default.removeItem(at: directory) }
}
