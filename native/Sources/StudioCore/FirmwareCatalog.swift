import CryptoKit
import Foundation

/// One IPSW restore image hosted by Apple, shared by one or more devices.
public struct Firmware: Identifiable, Equatable, Sendable {
    public var id: String { url.absoluteString }
    public let url: URL
    public let version: String
    public let build: String
    /// SHA-1 Apple publishes for the IPSW file.
    public let sha1: String?
    public let devices: [String]
    public var fileName: String { url.lastPathComponent }
    public var family: DeviceNames.Family { DeviceNames.family(of: devices.first ?? "") }
    public var design: DeviceNames.Design { DeviceNames.design(of: devices.last ?? "") }
    public var platform: String {
        devices.allSatisfy { $0.hasPrefix("iPad") } && (Int(version.split(separator: ".").first ?? "") ?? 0) >= 13 ? "iPadOS" : "iOS"
    }
    public var deviceNames: [String] {
        var seen = Set<String>()
        return devices.map(DeviceNames.name(for:)).filter { seen.insert($0).inserted }
    }
    public func matches(query: String) -> Bool {
        let text = ([version, build, platform] + devices + deviceNames).joined(separator: " ")
        return query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
    }
}

/// Apple's public device software list (the one Finder uses to restore iPhone and iPad).
public enum FirmwareCatalog {
    public static let url = URL(string: "https://s.mzstatic.com/version")!

    /// Current restore images for iPhone, iPad and iPod touch: per device only its newest version.
    public static func parse(_ data: Data) -> [Firmware] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let byVersion = plist["MobileDeviceSoftwareVersionsByVersion"] as? [String: Any] else { return [] }
        struct Entry { var version: String; var build: String; var sha1: String?; var devices: Set<String> }
        var entries: [URL: Entry] = [:]
        for case let block as [String: Any] in byVersion.values {
            guard let byDevice = block["MobileDeviceSoftwareVersions"] as? [String: Any] else { continue }
            for (device, value) in byDevice where ["iPhone", "iPad", "iPod"].contains(where: { device.hasPrefix($0) }) {
                guard let builds = value as? [String: Any] else { continue }
                for case let build as [String: Any] in builds.values {
                    let universal = (build["Universal"] as? [String: Any])?["Restore"]
                    for case let restore as [String: Any] in [build["Restore"], universal].compactMap({ $0 }) {
                        guard let url = trustedURL(restore["FirmwareURL"] as? String),
                              let version = restore["ProductVersion"] as? String, Installer.validVersion(version) || version.range(of: #"^\d+$"#, options: .regularExpression) != nil,
                              let buildVersion = restore["BuildVersion"] as? String, buildVersion.range(of: "^[0-9A-Za-z]+$", options: .regularExpression) != nil
                        else { continue }
                        let sha1 = (restore["FirmwareSHA1"] as? String).flatMap { $0.range(of: "^[0-9a-fA-F]{40}$", options: .regularExpression) != nil ? $0.lowercased() : nil }
                        var entry = entries[url] ?? Entry(version: version, build: buildVersion, sha1: sha1, devices: [])
                        entry.devices.insert(device)
                        if entry.sha1 == nil { entry.sha1 = sha1 }
                        entries[url] = entry
                    }
                }
            }
        }
        // Newest version per device.
        var newest: [String: String] = [:]
        for entry in entries.values {
            for device in entry.devices where newest[device].map({ entry.version.compare($0, options: .numeric) == .orderedDescending }) ?? true {
                newest[device] = entry.version
            }
        }
        return entries.compactMap { url, entry -> Firmware? in
            let current = entry.devices.filter { newest[$0] == entry.version }
            guard !current.isEmpty else { return nil }
            return Firmware(url: url, version: entry.version, build: entry.build, sha1: entry.sha1,
                            devices: current.sorted { DeviceNames.order($0, $1) })
        }.sorted { DeviceNames.newestFirst($0.devices.last ?? "", $1.devices.last ?? "") }
    }

    /// Apple hosts only, always over HTTPS (the list still contains some http:// links).
    static func trustedURL(_ value: String?) -> URL? {
        guard let value, var components = URLComponents(string: value), let host = components.host?.lowercased(),
              host == "apple.com" || host.hasSuffix(".apple.com") || host.hasSuffix(".cdn-apple.com") else { return nil }
        if host == "updates-http.cdn-apple.com" { components.host = "updates.cdn-apple.com" }
        components.scheme = "https"
        return components.url
    }

    public static func sha1(of url: URL, isCancelled: () -> Bool = { false }) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = Insecure.SHA1()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            if isCancelled() { throw CancellationError() }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
