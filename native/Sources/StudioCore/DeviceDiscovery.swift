import Foundation

/// Finds iPhones, iPads and Macs newer than this app: Apple's own lists name every supported device by its
/// model identifier; for identifiers the app does not know, name and details come from AppleDB (appledb.dev).
public enum DeviceDiscovery {
    /// Apple's macOS restore list: every Mac with Apple silicon that the newest macOS supports.
    public static let macRestoreFeed = URL(string: "https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml")!

    /// Mac identifier → newest macOS version Apple lists for it.
    public static func macs(fromRestoreFeed data: Data) -> [String: String] {
        var result: [String: String] = [:]
        for (device, restore) in restores(data) where isMac(device) {
            guard let version = restore["ProductVersion"] as? String, Installer.validVersion(version) || version.range(of: #"^\d+$"#, options: .regularExpression) != nil else { continue }
            if result[device].map({ version.compare($0, options: .numeric) == .orderedDescending }) ?? true { result[device] = version }
        }
        return result
    }

    /// iPhone, iPad and iPod identifiers in Apple's device software list (FirmwareCatalog.url).
    public static func mobileIdentifiers(fromDeviceList data: Data) -> Set<String> {
        Set(restores(data).map(\.device).filter { ["iPhone", "iPad", "iPod"].contains(where: $0.hasPrefix) && valid($0) })
    }

    /// Only plain model identifiers such as "iPad19,1" or "Mac18,2" are looked up.
    public static func valid(_ identifier: String) -> Bool {
        identifier.range(of: #"^(iPhone|iPad|iPod|Mac|MacBook|MacBookAir|MacBookPro|Macmini|MacPro|iMac|iMacPro)\d{1,3},\d{1,3}$"#, options: .regularExpression) != nil
    }
    public static func isMac(_ identifier: String) -> Bool { valid(identifier) && !["iPhone", "iPad", "iPod"].contains(where: identifier.hasPrefix) }

    public static func appleDBURL(for identifier: String) -> URL? {
        valid(identifier) ? URL(string: "https://api.appledb.dev/device/\(identifier).json") : nil
    }

    /// The parts of an AppleDB device record the app uses.
    public struct Record: Codable, Equatable, Sendable {
        public let name: String
        public let type: String?
        public let soc: String?
        public let released: String?
        public let models: [String]
        public init(name: String, type: String?, soc: String?, released: String?, models: [String]) {
            self.name = name; self.type = type; self.soc = soc; self.released = released; self.models = models
        }
    }

    /// Parses an AppleDB record; refuses records for another identifier and implausible text.
    public static func record(fromAppleDB data: Data, identifier: String) -> Record? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = json["identifier"] as? [String], ids.contains(identifier),
              let name = (json["name"] as? String).map(clean), plausible(name) else { return nil }
        func text(_ key: String) -> String? { (json[key] as? String).map(clean).flatMap { plausible($0) ? $0 : nil } }
        let models = ((json["model"] as? [String]) ?? []).filter { $0.range(of: "^A[0-9]{4}$", options: .regularExpression) != nil }
        let released = (json["released"] as? String).flatMap { $0.range(of: #"^\d{4}(-\d{2}(-\d{2})?)?$"#, options: .regularExpression) != nil ? $0 : nil }
        return Record(name: name, type: text("type"), soc: text("soc"), released: released, models: models)
    }
    private static func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func plausible(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 90 && text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    /// Name without connectivity variants, so Wi-Fi and Cellular models share one name ("iPad mini (A20 Pro)").
    public static func displayName(_ record: Record) -> String {
        var name = record.name
        for suffix in [" Wi-Fi + Cellular", " (Wi-Fi + Cellular)", " Wi-Fi", " (Wi-Fi)", " (GSM)", " (CDMA)", " (Global)", " (China)"] where name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name
    }

    /// A model entry for "Mac suchen" built from Apple's restore list and AppleDB.
    public static func macModel(identifier: String, record: Record, newestMacOS version: String) -> MacModel {
        let type = record.type ?? "Mac"
        let categories = ["MacBook Pro", "MacBook Air", "MacBook Neo", "MacBook", "iMac", "Mac mini", "Mac Studio", "Mac Pro"]
        let category = categories.first { type == $0 } ?? "Mac"
        let icon: String = switch category {
        case "MacBook Pro": "macbook_pro_m_series.png"
        case "MacBook Air", "MacBook Neo", "MacBook": "macbook_air_m_series.png"
        case "iMac": "imac_m_series.png"
        case "Mac Studio": "mac_studio.png"
        case "Mac Pro": "mac_pro.png"
        default: "mac_mini.png"
        }
        let major = String(version.split(separator: ".").first ?? "")
        let full = AppleCatalog.marketingName(version: version).map { "\($0) \(major)" } ?? "macOS \(major)"
        let short = AppleCatalog.marketingName(version: version).map { $0.replacingOccurrences(of: "macOS ", with: "") } ?? "macOS \(major)"
        let year = record.released.flatMap { Int($0.prefix(4)) } ?? Calendar(identifier: .gregorian).component(.year, from: Date())
        return MacModel(name: displayName(record), category: category, year: year, identifiers: [identifier], model_numbers: record.models,
                        cpu: record.soc.map { "Apple \($0)" } ?? "Apple Silicon", hw_icon: icon, arch: "Apple Silicon",
                        min_macos: full, max_macos: full, supported_versions: [short],
                        notes: String(localized: "Automatisch erkannt: in Apples macOS-Liste enthalten, Angaben von AppleDB. Ältere macOS-Versionen sind nicht bekannt."))
    }

    private static func restores(_ data: Data) -> [(device: String, values: [String: Any])] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let byVersion = plist["MobileDeviceSoftwareVersionsByVersion"] as? [String: Any] else { return [] }
        var result: [(String, [String: Any])] = []
        for case let block as [String: Any] in byVersion.values {
            for (device, value) in (block["MobileDeviceSoftwareVersions"] as? [String: Any]) ?? [:] {
                for case let build as [String: Any] in ((value as? [String: Any]) ?? [:]).values {
                    let universal = (build["Universal"] as? [String: Any])?["Restore"]
                    for case let restore as [String: Any] in [build["Restore"], universal].compactMap({ $0 }) { result.append((device, restore)) }
                }
            }
        }
        return result
    }
}
