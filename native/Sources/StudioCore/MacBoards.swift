import Foundation

/// Names for Apple's hardware IDs ("J316cAP", "Mac-…") that macOS installers list as supported.
/// The table comes from AppleDB's device list (appledb.dev), which records each Mac's board IDs.
public enum MacBoards {
    public static let url = URL(string: "https://api.appledb.dev/device/main.json")!

    public struct Mac: Codable, Equatable, Sendable {
        public let name: String
        public let type: String
        public let identifiers: [String]
        public init(name: String, type: String, identifiers: [String]) { self.name = name; self.type = type; self.identifiers = identifiers }
    }

    /// Lowercased board ID → Mac. Only Macs are kept; other devices and implausible entries are skipped.
    public static func table(fromAppleDB data: Data) -> [String: Mac] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var result: [String: Mac] = [:]
        for entry in list {
            let identifiers = (entry["identifier"] as? [String] ?? []).filter(DeviceDiscovery.isMac)
            guard !identifiers.isEmpty, let name = text(entry["name"]) else { continue }
            let type = text(entry["type"]) ?? "Mac"
            for case let board as String in entry["board"] as? [String] ?? [] {
                let id = board.lowercased()
                guard id.range(of: "^[a-z0-9-]{2,40}$", options: .regularExpression) != nil, result[id] == nil else { continue }
                result[id] = Mac(name: name, type: type, identifiers: identifiers)
            }
        }
        return result
    }

    /// What a build is for, ready to be worded by the app.
    public enum Summary: Equatable, Sendable {
        /// One or two models, by full name.
        case names([String])
        /// Several models of up to three product lines, e.g. ("MacBook Pro", 4).
        case types([(type: String, count: Int)])
        /// Many models across product lines.
        case many(Int)

        public static func == (a: Summary, b: Summary) -> Bool {
            switch (a, b) {
            case let (.names(x), .names(y)): return x == y
            case let (.many(x), .many(y)): return x == y
            case let (.types(x), .types(y)): return x.map(\.type) == y.map(\.type) && x.map(\.count) == y.map(\.count)
            default: return false
            }
        }
    }

    /// Distinct model names for the given board IDs, sorted; unknown IDs are left out.
    public static func names(for devices: [String], in table: [String: Mac]) -> [Mac] {
        var seen = Set<String>()
        return devices.compactMap { table[$0.lowercased()] }.filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func summary(for devices: [String], in table: [String: Mac]) -> Summary? {
        let macs = names(for: devices, in: table)
        guard !macs.isEmpty else { return nil }
        if macs.count <= 2 { return .names(macs.map(\.name)) }
        var counts: [(type: String, count: Int)] = []
        for mac in macs {
            if let index = counts.firstIndex(where: { $0.type == mac.type }) { counts[index].count += 1 } else { counts.append((mac.type, 1)) }
        }
        return counts.count <= 3 ? .types(counts.sorted { $0.count == $1.count ? $0.type < $1.type : $0.count > $1.count }) : .many(macs.count)
    }

    private static func text(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 90, clean.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return clean
    }
}

/// All catalog builds of one macOS version: the build that fits best first, then builds for specific Macs.
public struct InstallerGroup: Identifiable, Equatable {
    public var id: String { primary.title + " " + primary.version }
    public let primary: Installer
    public let others: [Installer]

    /// Groups by title and version, keeping the list order of versions. Within a version the build running on
    /// this Mac comes first, then one Apple offers for this Mac, then the one that supports the most Macs.
    public static func groups(_ items: [Installer], hostBuild: String = HostSystem.build) -> [InstallerGroup] {
        var order: [String] = []
        var buckets: [String: [(Int, Installer)]] = [:]
        for (index, item) in items.enumerated() {
            let key = item.title + "\u{1F}" + item.version
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append((index, item))
        }
        return order.map { key in
            let sorted = buckets[key]!.sorted { a, b in
                func rank(_ item: Installer) -> (Int, Int, Int) {
                    (!hostBuild.isEmpty && item.build.caseInsensitiveCompare(hostBuild) == .orderedSame ? 0 : 1,
                     item.offeredForThisMac ? 0 : 1,
                     -item.supportedDevices.count)
                }
                let x = rank(a.1), y = rank(b.1)
                return x != y ? x < y : a.0 < b.0
            }.map(\.1)
            return InstallerGroup(primary: sorted[0], others: Array(sorted.dropFirst()))
        }
    }
}
