import Foundation

public struct Installer: Identifiable, Equatable {
    public var id: String { version + build }
    public let title: String
    public let version: String
    public let build: String
    public let bytes: Double
    /// InstallAssistant.pkg from Apple's public catalog; used when softwareupdate does not offer this version for the current Mac.
    public var packageURL: URL?
    /// All catalog files for this installer (one InstallAssistant.pkg, or the 10.13–10.15 set).
    public var packageParts: [CatalogPart] = []
    /// macOS 10.13–10.15 from the catalog: assembled without the macOS installer, no administrator password.
    public var assembledFromParts: Bool { !packageParts.isEmpty && packageParts[0].name != "InstallAssistant.pkg" }
    /// OS X 10.10 – macOS 10.12: one Apple disk image with the installer package inside.
    public var fromDiskImage: Bool { packageParts.count == 1 && packageParts[0].name.hasSuffix(".dmg") }
    /// True when `softwareupdate --list-full-installers` offers this installer on the current Mac.
    public var offeredForThisMac: Bool
    /// Apple's hardware IDs (board or device IDs, lowercased) this build installs on; empty when unknown or for every Mac.
    public var supportedDevices: [String] = []
    public init(title: String, version: String, build: String = "Manuell", bytes: Double = 0,
                packageURL: URL? = nil, packageParts: [CatalogPart] = [], offeredForThisMac: Bool = true, supportedDevices: [String] = []) {
        self.title = title; self.version = version; self.build = build; self.bytes = bytes
        self.packageURL = packageURL; self.packageParts = packageParts; self.offeredForThisMac = offeredForThisMac
        self.supportedDevices = supportedDevices
    }
    public static func parse(_ text: String) -> [Installer] {
        let pattern = #"Title:\s*([^,]+),\s*Version:\s*([^,]+),\s*Size:\s*(\d+)\s*KiB,\s*Build:\s*([^,\r\n]+)"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            func field(_ n: Int) -> String { ns.substring(with: match.range(at: n)).trimmingCharacters(in: .whitespaces) }
            return Installer(title: field(1), version: field(2), build: field(4), bytes: (Double(field(3)) ?? 0) * 1024)
        }.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
    public static func validVersion(_ version: String) -> Bool {
        version.range(of: #"^\d+(\.\d+){1,2}$"#, options: .regularExpression) != nil
    }
}

public struct ProgressSample: Equatable {
    public let phase: String
    public let percent: Double
    public static func parse(_ text: String) -> ProgressSample? {
        let regex = try! NSRegularExpression(pattern: #"(Installing|Downloading):\s*(\d+(?:\.\d+)?)\s*%"#, options: .caseInsensitive)
        let ns = text as NSString
        guard let m = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).last,
              let value = Double(ns.substring(with: m.range(at: 2))) else { return nil }
        return ProgressSample(phase: ns.substring(with: m.range(at: 1)).lowercased(), percent: min(100, max(0, value)))
    }
}

public struct ProgressMetrics {
    private var previous: (time: TimeInterval, bytes: Double, phase: String)?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func update(_ sample: ProgressSample, total: Double, time: TimeInterval) -> (bytes: Double?, mbits: Double?) {
        guard total > 0 else { return (nil, nil) }
        let bytes = total * sample.percent / 100
        var rate: Double?
        if let old = previous, old.phase == sample.phase, time - old.time >= 1, bytes > old.bytes, sample.percent < 100 {
            rate = (bytes - old.bytes) * 8 / (time - old.time) / 1_000_000
        }
        if previous == nil || previous!.phase != sample.phase || time - previous!.time >= 1 || bytes < previous!.bytes {
            previous = (time, bytes, sample.phase)
        }
        return (bytes, rate)
    }
}

public struct MacModel: Decodable, Identifiable {
    public var id: String { name }
    public let name: String
    public let category: String
    public let year: Int
    public let identifiers: [String]
    public let model_numbers: [String]?
    public let cpu: String
    public let hw_icon: String
    public let arch: String
    public let min_macos: String
    public let max_macos: String
    public let supported_versions: [String]
    public let notes: String
    public init(name: String, category: String, year: Int, identifiers: [String], model_numbers: [String]?, cpu: String,
                hw_icon: String, arch: String, min_macos: String, max_macos: String, supported_versions: [String], notes: String) {
        self.name = name; self.category = category; self.year = year; self.identifiers = identifiers
        self.model_numbers = model_numbers; self.cpu = cpu; self.hw_icon = hw_icon; self.arch = arch
        self.min_macos = min_macos; self.max_macos = max_macos; self.supported_versions = supported_versions; self.notes = notes
    }
    public func matches(query: String) -> Bool {
        let text = "\(name) \(year) \(identifiers.joined(separator: " ")) \((model_numbers ?? []).joined(separator: " ")) \(cpu)"
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
    }
    public static func isSerialQuery(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return value.range(of: "^[A-Z0-9]{10,12}$", options: .regularExpression) != nil
            && value.rangeOfCharacter(from: .decimalDigits) != nil
            && value.rangeOfCharacter(from: .letters) != nil
    }
    public func supports(_ installer: Installer) -> Bool {
        supported_versions.contains { installer.title.localizedCaseInsensitiveContains($0) }
    }
}

public struct ExternalDisk: Identifiable, Equatable {
    public var id: String { identifier }
    public let name: String
    public let mount: String
    public let identifier: String
    public let uuid: String
    public let bytes: Double
    public static func validated(_ info: [String: Any]) -> ExternalDisk? {
        guard let internalDisk = info["Internal"] as? Bool, !internalDisk,
              let mount = info["MountPoint"] as? String, mount.hasPrefix("/Volumes/"),
              let identifier = info["DeviceIdentifier"] as? String,
              let uuid = info["VolumeUUID"] as? String, !uuid.isEmpty,
              (info["BusProtocol"] as? String) == "USB",
              let size = info["TotalSize"] as? NSNumber, size.doubleValue > 0 else { return nil }
        return ExternalDisk(name: info["VolumeName"] as? String ?? URL(fileURLWithPath: mount).lastPathComponent,
                            mount: mount, identifier: identifier, uuid: uuid, bytes: size.doubleValue)
    }
}

public func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
public func appleScriptQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
}
