import Foundation

/// Runs an elevated command in Terminal so that Terminal (not the system authtrampoline)
/// is the responsible process for macOS privacy control. createinstallmedia needs that
/// to write `.IAPhysicalMedia` on the freshly erased USB volume.
public struct TerminalJob {
    public let directory: URL
    public var script: URL { directory.appendingPathComponent("USB-Stick erstellen.command") }
    public var statusFile: URL { directory.appendingPathComponent("status") }
    public var logFile: URL { directory.appendingPathComponent("output.log") }
    /// Created by the app to ask the root command to stop (before erasing, or by ending createinstallmedia).
    public var cancelFile: URL { directory.appendingPathComponent("cancel") }
    /// PID of the Terminal shell running the script; lets the app notice a closed Terminal window.
    public var pidFile: URL { directory.appendingPathComponent("pid") }

    /// Exit codes of the USB root command besides createinstallmedia's own.
    public static let targetChangedExit: Int32 = 3
    public static let preparationFailedExit: Int32 = 4
    public static let noWriteAccessExit: Int32 = 77
    public static let cancelledExit: Int32 = 130

    public init(directory: URL) { self.directory = directory }

    /// zsh script: sudo runs the already safety-checked root command, output is mirrored into the log,
    /// and the exit status is written atomically for the app to pick up.
    public func scriptText(rootCommand: String, headline: String) -> String {
        let status = shellQuote(statusFile.path)
        return """
        #!/bin/zsh
        print -r -- "$$" > \(shellQuote(pidFile.path))
        clear
        print -r -- \(shellQuote(headline))
        print -r -- 'Bitte dein Mac-Passwort eingeben. Die Eingabe bleibt unsichtbar.'
        print
        /usr/bin/sudo /usr/bin/script -q -F \(shellQuote(logFile.path)) /bin/bash -c \(shellQuote(rootCommand))
        code=$?
        print -r -- "$code" > \(shellQuote(statusFile.path + ".tmp")) && /bin/mv \(shellQuote(statusFile.path + ".tmp")) \(status)
        print
        if [[ $code -eq 0 ]]; then print 'Fertig. Du kannst dieses Fenster schließen.'; else print "Fehlgeschlagen (Code $code). Details stehen auch in macOS Studio."; fi
        """ + "\n"
    }

    /// Creates a fresh private (0700) directory and a read/execute-only (0500) script.
    /// An existing directory is never reused, so nothing prepared beforehand can end up in the root command's folder.
    public func write(rootCommand: String, headline: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Data(scriptText(rootCommand: rootCommand, headline: headline).utf8).write(to: script, options: .withoutOverwriting)
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: script.path)
    }

    /// Exit status once Terminal has finished, otherwise nil.
    public func exitStatus() -> Int32? {
        guard let text = try? String(contentsOf: statusFile, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    /// Whether the Terminal shell is still running: nil until it has started (no PID written yet).
    public func shellRunning() -> Bool? {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return nil }
        return kill(pid, 0) == 0 || errno == EPERM
    }
    public func requestCancel() { try? Data().write(to: cancelFile) }
    public var cancelRequested: Bool { FileManager.default.fileExists(atPath: cancelFile.path) }

    /// Root command for the USB stick. Order: verify target → stop if cancelled → probe write access
    /// as the Terminal-attributed root process (fails before anything is erased if macOS denies it)
    /// → optional APFS preparation → createinstallmedia in the background, ended if cancel is requested.
    /// `application`: passed as --applicationpath for macOS 10.13 and older, whose createinstallmedia needs it.
    public func usbRootCommand(safety: String, mount: String, setup: String?, tool: String, volume: String, application: String? = nil) -> String {
        let cancel = shellQuote(cancelFile.path)
        let probe = shellQuote(mount + "/.macOSStudio-Schreibtest")
        var lines = [
            "echo " + shellQuote(USBProgress.checkMarker),
            "if ! { " + safety + "; }; then echo 'Das Ziel-Laufwerk hat sich geändert. Abbruch ohne Änderung.'; exit \(Self.targetChangedExit); fi",
            "if [ -e " + cancel + " ]; then echo " + shellQuote(USBProgress.cancelMarker) + "; exit \(Self.cancelledExit); fi",
            "if ! ( : > " + probe + " ) 2>/dev/null; then echo " + shellQuote(USBProgress.noAccessMarker) + "; exit \(Self.noWriteAccessExit); fi",
            "/bin/rm -f " + probe
        ]
        if let setup {
            lines.append("echo " + shellQuote(USBProgress.prepareMarker))
            lines.append("if ! { " + setup + "; }; then echo 'Vorbereitung des USB-Sticks fehlgeschlagen.'; exit \(Self.preparationFailedExit); fi")
        }
        lines += [
            "echo " + shellQuote(USBProgress.startMarker),
            shellQuote(tool) + " --volume " + shellQuote(volume) + (application.map { " --applicationpath " + shellQuote($0) } ?? "") + " --nointeraction &",
            "pid=$!",
            "while /bin/kill -0 \"$pid\" 2>/dev/null; do",
            "  if [ -e " + cancel + " ]; then echo; echo " + shellQuote(USBProgress.cancelMarker) + "; /bin/kill -TERM \"$pid\"; sleep 5; /bin/kill -KILL \"$pid\" 2>/dev/null; wait \"$pid\"; exit \(Self.cancelledExit); fi",
            "  sleep 1",
            "done",
            "wait \"$pid\""
        ]
        return lines.joined(separator: "\n")
    }
    public func output() -> String { (try? String(contentsOf: logFile, encoding: .utf8)) ?? "" }
    public func remove() { try? FileManager.default.removeItem(at: directory) }
}
