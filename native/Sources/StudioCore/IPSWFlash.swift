import Foundation

/// What an IPSW file says about itself (read from its Restore.plist / BuildManifest.plist).
public struct IPSWInfo: Equatable, Sendable {
    public let version: String
    public let build: String
    public let productTypes: [String]

    public init(version: String, build: String, productTypes: [String]) {
        self.version = version; self.build = build; self.productTypes = productTypes
    }

    /// Parses Restore.plist or BuildManifest.plist. Only iPhone/iPad/iPod restore images are accepted.
    public static func parse(_ data: Data) -> IPSWInfo? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let version = plist["ProductVersion"] as? String ?? ""
        let build = (plist["ProductBuildVersion"] as? String) ?? (plist["BuildVersion"] as? String) ?? ""
        let types = (plist["SupportedProductTypes"] as? [String] ?? [])
            .filter { ["iPhone", "iPad", "iPod"].contains(where: $0.hasPrefix) }
        guard !version.isEmpty, !types.isEmpty else { return nil }
        return IPSWInfo(version: version, build: build, productTypes: types)
    }

    public func supports(_ productType: String) -> Bool { productTypes.contains(productType) }
    public var platform: String {
        productTypes.allSatisfy { $0.hasPrefix("iPad") } && (Int(version.split(separator: ".").first ?? "") ?? 0) >= 13 ? "iPadOS" : "iOS"
    }
}

/// A device as Apple Configurator's `cfgutil list` reports it – in normal, recovery or DFU mode.
public struct FlashDevice: Identifiable, Equatable, Sendable {
    public var id: String { ecid }
    public let ecid: String
    public let productType: String
    public let name: String
    public let udid: String?
    /// USB location (same value as IOKit's "locationID") – matches the device on USB in every mode.
    public let locationID: Int?
    public var modelName: String { productType.isEmpty ? "Unbekanntes Gerät" : DeviceNames.name(for: productType) }

    public init(ecid: String, productType: String, name: String, udid: String?, locationID: Int? = nil) {
        self.ecid = ecid; self.productType = productType; self.name = name; self.udid = udid; self.locationID = locationID
    }
}

/// Restores iPhone/iPad from an IPSW through Apple Configurator's command line tool.
public enum CfgUtil {
    public static let candidates = [
        "/Applications/Apple Configurator.app/Contents/MacOS/cfgutil",
        "/Applications/Apple Configurator 2.app/Contents/MacOS/cfgutil",
        "/usr/local/bin/cfgutil"
    ]
    public static let appStore = URL(string: "macappstore://apps.apple.com/app/id1037126344")!

    public static func locate(_ exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        candidates.first(where: exists)
    }

    /// ECIDs come from cfgutil itself; only hex (0x…) or decimal numbers are passed back to it.
    public static func validECID(_ value: String) -> Bool {
        value.range(of: "^(0x[0-9A-Fa-f]{1,16}|[0-9]{1,20})$", options: .regularExpression) != nil
    }

    public static let listArguments = ["--format", "JSON", "list"]
    /// Seconds cfgutil waits for the device to show up. Through docks and hubs the device needs longer
    /// to re-appear after each restart during a restore, so wait generously.
    public static let deviceTimeout = "180"

    /// Worth an automatic new attempt: the connection dropped or the device was in the wrong state – typical
    /// with docks/hubs. Not for signing, file or version problems, where a retry cannot help.
    public static func isRetryable(_ output: String) -> Bool {
        let codes = errorCodes(in: output)
        let hopeless: Set<Int> = [3194, 3004, 3013, 3014, 3015, 3200, 17, 1638, 14, 1004, 1013, 1014, 1015, 10, 45, 1110]
        if codes.contains(where: { hopeless.contains(abs($0)) }) { return false }
        let lower = output.lowercased()
        if lower.contains("not compatible") || lower.contains("no space") || lower.contains("nicht kompatibel") { return false }
        return true
    }

    /// `cfgutil -e <ECID> --progress restore -I <ipsw>` – erases the device and installs exactly this IPSW.
    public static func restoreArguments(ecid: String, ipsw: URL) -> [String]? {
        guard validECID(ecid), ipsw.isFileURL, ipsw.pathExtension.lowercased() == "ipsw" else { return nil }
        return ["-e", ecid, "--timeout", deviceTimeout, "--progress", "restore", "-I", ipsw.path]
    }

    /// Repair actions for a device in recovery or DFU mode, like Apple Configurator's "Revive" and "Restore".
    public enum Repair: Sendable {
        case revive         // reinstalls the system, keeps data (Apple: "stuck in recovery mode")
        case restoreLatest  // downloads the latest signed iOS/iPadOS and erases everything
    }
    /// `cfgutil -e <ECID> --progress revive` / `… restore` (no IPSW: cfgutil loads the newest signed version).
    public static func repairArguments(ecid: String, _ repair: Repair) -> [String]? {
        guard validECID(ecid) else { return nil }
        return ["-e", ecid, "--timeout", deviceTimeout, "--progress", repair == .revive ? "revive" : "restore"]
    }

    /// Numeric ECID from cfgutil's 0x-hex or decimal form.
    public static func ecidValue(_ cfgutil: String) -> UInt64? {
        guard validECID(cfgutil) else { return nil }
        return cfgutil.lowercased().hasPrefix("0x") ? UInt64(cfgutil.dropFirst(2), radix: 16) : UInt64(cfgutil)
    }
    /// cfgutil reports ECIDs as 0x-hex or decimal; iBoot's USB serial always as plain hex.
    public static func sameECID(cfgutil: String, usbHex: String) -> Bool {
        guard validECID(cfgutil), let usb = UInt64(usbHex, radix: 16) else { return false }
        let value = cfgutil.lowercased().hasPrefix("0x") ? UInt64(cfgutil.dropFirst(2), radix: 16) : UInt64(cfgutil)
        return value == usb
    }

    /// Parses `cfgutil --format JSON list`. Unknown shapes yield an empty list rather than a guess.
    public static func devices(fromList data: Data) -> [FlashDevice] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var entries: [[String: Any]] = []
        if let output = json["Output"] as? [String: Any] {
            entries = output.values.compactMap { $0 as? [String: Any] }
        } else if let output = json["Output"] as? [[String: Any]] {
            entries = output
        }
        func value(_ entry: [String: Any], _ keys: String...) -> String? {
            for (key, raw) in entry where keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
                if let text = raw as? String, !text.isEmpty { return text }
                if let number = raw as? NSNumber { return "0x" + String(number.uint64Value, radix: 16, uppercase: true) }
            }
            return nil
        }
        var seen = Set<String>()
        return entries.compactMap { entry -> FlashDevice? in
            guard let ecid = value(entry, "ECID"), validECID(ecid), seen.insert(ecid.lowercased()).inserted else { return nil }
            let type = value(entry, "deviceType", "productType", "Type") ?? ""
            let location = (entry["locationID"] as? NSNumber)?.intValue
            return FlashDevice(ecid: ecid, productType: type, name: value(entry, "name", "deviceName") ?? "", udid: value(entry, "UDID"), locationID: location)
        }
        .sorted { ($0.productType, $0.ecid) < ($1.productType, $1.ecid) }
    }

    /// Overall progress of a cfgutil restore. cfgutil prints "Step 3 of 7: Name" (German: "Schritt 3 von 7: …")
    /// followed by percentages that restart at 0 for every step – shown raw they jump around.
    public struct StepProgress: Equatable, Sendable {
        public private(set) var step = 0
        public private(set) var total = 0
        public private(set) var stepPercent: Double = 0
        public private(set) var title = ""
        private var partial = ""
        private var best: Double = 0
        public init() {}

        /// 0…100 across all steps; never goes backwards. nil until cfgutil reports its steps.
        public var overall: Double? {
            guard total > 0, step > 0 else { return nil }
            return best
        }

        public mutating func consume(_ chunk: String) {
            let text = partial + chunk
            var lines = text.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            partial = lines.removeLast()            // may be an incomplete line
            for line in lines { read(line) }
            if partial.count > 400 { read(partial); partial = "" }
        }

        private mutating func read(_ line: String) {
            let pattern = try! NSRegularExpression(pattern: #"(?:Step|Schritt)\s+(\d+)\s+(?:of|von)\s+(\d+)\s*:?\s*(.*)"#)
            var rest = line
            if let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let n = Range(match.range(at: 1), in: line).flatMap({ Int(line[$0]) }),
               let m = Range(match.range(at: 2), in: line).flatMap({ Int(line[$0]) }), m > 0, n >= 1, n <= m {
                if n != step { stepPercent = 0 }
                step = n; total = m
                let name = Range(match.range(at: 3), in: line).map { String(line[$0]) } ?? ""
                title = name.replacingOccurrences(of: #"\s*\d{1,3}(?:[.,]\d+)?\s?%.*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                rest = name
            }
            if step > 0, let value = CfgUtil.percent(in: rest) { stepPercent = value }
            if total > 0, step > 0 {
                best = max(best, min(100, (Double(step - 1) + stepPercent / 100) / Double(total) * 100))
            }
        }
    }

    /// Why a cfgutil job failed, in plain German: the meaningful last lines of its output plus an
    /// explanation for the restore error codes Apple documents (support.apple.com/HT201444 / 118106).
    public static func failureReport(_ output: String, viaHub: Bool) -> String {
        let lines = output.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("{") && CfgUtil.percent(in: $0) == nil || $0.lowercased().contains("error") }
        var detail = Array(lines.suffix(6))
        if detail.isEmpty { detail = ["Keine Details von cfgutil."] }
        var text = detail.joined(separator: "\n")
        let codes = errorCodes(in: output)
        if let hint = codes.lazy.compactMap({ explain($0) }).first {
            text = hint + "\n\n" + text
        } else if output.lowercased().contains("timed out") || output.lowercased().contains("timeout") {
            text = "Das Gerät hat zu lange nicht geantwortet – oft eine wackelige USB-Verbindung." + "\n\n" + text
        }
        if viaHub {
            text += "\n\nDas Gerät hängt an einem USB-Hub/Dock. Die App hat bereits automatisch erneut versucht. Hilft das nicht: anderen Dock-Anschluss oder ein anderes Kabel nehmen – oder direkt am Mac anschließen."
        }
        return text
    }

    /// Numbers that look like restore error codes ("error 4013", "(AMRestoreErrorDomain 4013)", "Code=4013").
    public static func errorCodes(in text: String) -> [Int] {
        let pattern = try! NSRegularExpression(pattern: #"(?i)(?:error|fehler|code\s*[=:]?|domain)\s*[:=]?\s*\(?\s*(-?\d{1,5})\b|\(\s*[A-Za-z.]*(?:Domain|Error)[A-Za-z.]*\s+(-?\d{1,5})\s*\)"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            for group in [1, 2] {
                if let r = Range(match.range(at: group), in: text), let value = Int(text[r]) { return value }
            }
            return nil
        }
    }

    public static func explain(_ code: Int) -> String? {
        switch abs(code) {
        case 4005, 4013, 4014, 4000, 9, 4016:
            return "Fehler \(code): Die Verbindung zum Gerät ist während der Wiederherstellung abgerissen. Gerät direkt an den Mac anschließen (kein Hub/Dock), anderes Kabel oder anderen Anschluss probieren, dann erneut flashen – bei Bedarf wieder im DFU-Modus."
        case 3194, 3004, 3013, 3014, 3015, 3200, 17, 1638:
            return "Fehler \(code): Apples Server hat die Freigabe (Signatur) nicht erteilt oder war nicht erreichbar. Internetverbindung prüfen; nur von Apple aktuell freigegebene Versionen lassen sich installieren."
        case 1600, 1601, 1602, 1603, 1604, 1611, 1667, 1669:
            return "Fehler \(code): Das Gerät war nicht im erwarteten Modus oder die USB-Verbindung war gestört. Gerät erneut in den DFU-Modus bringen und direkt am Mac flashen."
        case 14, 1004, 1013, 1014, 1015:
            return "Fehler \(code): Die Firmware-Datei oder die Übertragung war fehlerhaft. Datei unter „Firmware laden“ mit „Prüfen“ kontrollieren oder neu laden; anderes Kabel probieren."
        case 10, 45, 1110:
            return "Fehler \(code): Diese Version passt nicht zum Gerät oder ist zu alt. Die neueste freigegebene Version verwenden."
        default:
            return nil
        }
    }

    /// Last percentage in a chunk of cfgutil output (0…100), if any.
    public static func percent(in text: String) -> Double? {
        let pattern = try! NSRegularExpression(pattern: #"(\d{1,3}(?:[.,]\d+)?)\s?%"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.matches(in: text, range: range).last,
              let r = Range(match.range(at: 1), in: text),
              let value = Double(text[r].replacingOccurrences(of: ",", with: ".")), value <= 100 else { return nil }
        return value
    }

    /// Last non-empty, readable line of output, for the status text.
    public static func lastLine(in text: String) -> String? {
        text.components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("{") }
            .map { String($0.prefix(160)) }
    }
}
