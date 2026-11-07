import Foundation

/// Apple's public software catalog lists every full installer, including versions the current Mac cannot run.
/// softwareupdate hides those, but they are needed to prepare USB installers for other Macs.
public enum AppleCatalog {
    public static let url = URL(string: "https://swscan.apple.com/content/catalogs/others/index-27-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz")!

    public struct Product: Equatable, Sendable {
        public let id: String
        public let distribution: URL
        /// InstallAssistant.pkg (macOS 11+) or InstallAssistantAuto.pkg (10.13–10.15).
        public let package: URL
        public let bytes: Double
        /// Every file that has to be downloaded; the first one is `package`.
        public let parts: [CatalogPart]
        /// macOS 10.13–10.15: the installer app is assembled from several files instead of installing one package.
        public var legacy: Bool { parts.count > 1 }
    }

    /// Files of a 10.13–10.15 installer, in download order. The first three are required.
    public static let legacyParts = ["InstallAssistantAuto.pkg", "InstallESDDmg.pkg", "BaseSystem.dmg",
                                     "BaseSystem.chunklist", "AppleDiagnostics.dmg", "AppleDiagnostics.chunklist"]

    /// Full installers only: products that ship an InstallAssistant.pkg (macOS 11 and later) or the
    /// InstallAssistantAuto.pkg + InstallESDDmg.pkg set of macOS 10.13–10.15.
    public static func products(fromCatalog data: Data) -> [Product] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let products = plist["Products"] as? [String: Any] else { return [] }
        return products.compactMap { id, value in
            guard let product = value as? [String: Any],
                  let packages = product["Packages"] as? [[String: Any]],
                  let distributions = product["Distributions"] as? [String: String],
                  let distribution = trustedURL(distributions["English"] ?? distributions["en"] ?? distributions.values.first)
            else { return nil }
            func part(_ name: String) -> CatalogPart? {
                guard let entry = packages.first(where: { ($0["URL"] as? String)?.hasSuffix("/" + name) == true }),
                      let url = trustedURL(entry["URL"] as? String) else { return nil }
                return CatalogPart(name: name, url: url, bytes: (entry["Size"] as? NSNumber)?.int64Value ?? 0,
                                   integrity: trustedURL(entry["IntegrityDataURL"] as? String))
            }
            var parts: [CatalogPart]
            if let full = part("InstallAssistant.pkg") {
                parts = [full]
            } else {
                parts = legacyParts.compactMap(part)
                guard parts.count >= 3, parts.prefix(3).map(\.name) == Array(legacyParts.prefix(3)) else { return nil }
            }
            return Product(id: id, distribution: distribution, package: parts[0].url,
                           bytes: Double(parts.reduce(Int64(0)) { $0 + $1.bytes }), parts: parts)
        }.sorted { $0.id < $1.id }
    }

    /// Title, version and build from a product's .dist file.
    public static func describe(distribution text: String) -> (title: String, version: String, build: String)? {
        func capture(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let version = capture(#"<key>VERSION</key>\s*<string>([^<]+)</string>"#),
              let build = capture(#"<key>BUILD</key>\s*<string>([^<]+)</string>"#),
              Installer.validVersion(version),
              build.range(of: "^[0-9A-Za-z]+$", options: .regularExpression) != nil else { return nil }
        // Older distributions carry a localisation key ("SU_TITLE") instead of a name.
        let title = capture(#"<title>([^<]+)</title>"#).map(decodeEntities).flatMap { $0.contains("SU_TITLE") ? nil : $0 }
            ?? marketingName(version: version) ?? "macOS \(version)"
        return (title, version, build)
    }

    /// Adds catalog-only installers to the ones softwareupdate offers. Offered entries win, but keep the package as fallback.
    public static func merge(offered: [Installer], catalog: [Installer]) -> [Installer] {
        var result = offered.map { item -> Installer in
            var copy = item; copy.offeredForThisMac = true
            if let match = catalog.first(where: { $0.version == item.version && $0.build == item.build }) {
                copy.packageURL = match.packageURL; copy.packageParts = match.packageParts
            }
            return copy
        }
        for item in catalog where !result.contains(where: { $0.version == item.version && $0.build == item.build }) {
            var copy = item; copy.offeredForThisMac = false
            result.append(copy)
        }
        return result.sorted {
            let order = $0.version.compare($1.version, options: .numeric)
            return order == .orderedSame ? $0.build > $1.build : order == .orderedDescending
        }
    }

    /// OS X Yosemite – macOS Sierra are not in the software catalog. Apple offers them as disk images
    /// (support article "How to download and install macOS"); the links and sizes are Apple's.
    public static let diskImageInstallers: [Installer] = [
        ("macOS Sierra", "10.12.6", "16G29", "https://updates.cdn-apple.com/2019/cert/061-39476-20191023-48f365f4-0015-4c41-9f44-39d3d2aca067/InstallOS.dmg", Int64(5_007_882_126)),
        ("OS X El Capitan", "10.11.6", "15G31", "https://updates.cdn-apple.com/2019/cert/061-41424-20191024-218af9ec-cf50-4516-9011-228c78eda3d2/InstallMacOSX.dmg", Int64(6_204_629_298)),
        ("OS X Yosemite", "10.10.5", "14F27", "https://updates.cdn-apple.com/2019/cert/061-41343-20191023-02465f92-3ab5-4c92-bfe2-b725447a070d/InstallMacOSX.dmg", Int64(5_718_074_248))
    ].map { title, version, build, link, bytes in
        let url = URL(string: link)!
        return Installer(title: title, version: version, build: build, bytes: Double(bytes), packageURL: url,
                         packageParts: [CatalogPart(name: url.lastPathComponent, url: url, bytes: bytes)], offeredForThisMac: false)
    }

    /// Names for distributions without a readable title.
    public static func marketingName(version: String) -> String? {
        let names = ["10.10": "OS X Yosemite", "10.11": "OS X El Capitan", "10.12": "macOS Sierra", "10.13": "macOS High Sierra",
                     "10.14": "macOS Mojave", "10.15": "macOS Catalina", "11": "macOS Big Sur", "12": "macOS Monterey",
                     "13": "macOS Ventura", "14": "macOS Sonoma", "15": "macOS Sequoia", "26": "macOS Tahoe", "27": "macOS Golden Gate"]
        let parts = version.split(separator: ".")
        guard let major = parts.first else { return nil }
        if major == "10", parts.count > 1 { return names["10.\(parts[1])"] }
        return names[String(major)]
    }

    /// Only Apple's HTTPS download hosts are accepted.
    static func trustedURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              host == "apple.com" || host.hasSuffix(".apple.com") else { return nil }
        return url
    }
    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}

/// One downloadable file of a catalog product, with Apple's chunked SHA-256 integrity data when published.
public struct CatalogPart: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let bytes: Int64
    public let integrity: URL?
    public init(name: String, url: URL, bytes: Int64, integrity: URL? = nil) {
        self.name = name; self.url = url; self.bytes = bytes; self.integrity = integrity
    }
}
