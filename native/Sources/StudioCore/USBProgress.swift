import Foundation

/// Live step and percentage from the createinstallmedia log (written by script(1) in Terminal).
public struct USBProgress: Equatable {
    public let step: String
    public let percent: Double?

    public init(step: String, percent: Double?) { self.step = step; self.percent = percent }

    /// Marker lines echoed by the root command before Apple's tool starts.
    public static let checkMarker = "▸ Ziel-Laufwerk wird geprüft"
    public static let prepareMarker = "▸ APFS-Stick wird als Mac OS Extended vorbereitet"
    public static let startMarker = "▸ createinstallmedia startet"
    public static let cancelMarker = "▸ Abbruch angefordert"
    public static let noAccessMarker = "▸ Kein Schreibzugriff für Terminal – USB-Stick bleibt unverändert"

    private static let phases: [(pattern: String, step: String)] = [
        (checkMarker, "Ziel-Laufwerk wird geprüft"),
        (prepareMarker, "USB-Stick wird vorbereitet (APFS → Mac OS Extended)"),
        (startMarker, "Apples createinstallmedia startet"),
        ("Ready to start", "Apples createinstallmedia startet"),
        ("Erasing disk", "USB-Stick wird gelöscht"),
        ("Making disk bootable", "USB-Stick wird bootfähig gemacht"),
        ("Making the disk bootable", "USB-Stick wird bootfähig gemacht"),
        ("Copying to disk", "Installer wird auf den USB-Stick kopiert"),
        ("Copying essential files", "Wichtige Systemdateien werden kopiert"),
        ("Copying the macOS RecoveryOS", "macOS-Wiederherstellung wird kopiert"),
        ("Copying boot files", "Startdateien werden kopiert"),
        ("Copying installer files", "Installer wird auf den USB-Stick kopiert"),
        ("Install media now available", "Fertig – USB-Stick ist bereit"),
        (cancelMarker, "Wird abgebrochen"),
        (noAccessMarker, "Kein Schreibzugriff für Terminal")
    ]

    /// Printable text: carriage returns become line breaks, terminal control characters are removed.
    public static func clean(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        text.unicodeScalars.removeAll { $0.value < 0x20 && $0 != "\n" && $0 != "\t" }
        return text
    }

    /// Latest known step; the percentage is the last value reported after that step began.
    public static func parse(_ log: String) -> USBProgress? {
        let text = clean(log)
        var latest: (range: Range<String.Index>, step: String)?
        for phase in phases {
            if let range = text.range(of: phase.pattern, options: [.backwards, .caseInsensitive]),
               latest == nil || range.lowerBound > latest!.range.lowerBound {
                latest = (range, phase.step)
            }
        }
        guard let latest else { return nil }
        let tail = String(text[latest.range.upperBound...])
        let regex = try! NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#)
        let ns = tail as NSString
        let value = regex.matches(in: tail, range: NSRange(location: 0, length: ns.length)).last
            .flatMap { Double(ns.substring(with: $0.range(at: 1))) }
        return USBProgress(step: latest.step, percent: value.map { min(100, max(0, $0)) })
    }
}
