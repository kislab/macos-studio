import Foundation

/// Apple's public software catalog lists every full installer, including versions the current Mac cannot run.
/// softwareupdate hides those, but they are needed to prepare USB installers for other Macs.
public enum AppleCatalog {
    public static let url = URL(string: "https://swscan.apple.com/content/catalogs/others/index-27-26-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog.gz")!

    public struct Product: Equatable, Sendable {
        public let id: String
        public let distribution: URL
        public let package: URL
        public let bytes: Double
    }

    /// Full installers only: products that ship an InstallAssistant.pkg (macOS 11 and later).
    public static func products(fromCatalog data: Data) -> [Product] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let products = plist["Products"] as? [String: Any] else { return [] }
        return products.compactMap { id, value in
            guard let product = value as? [String: Any],
                  let packages = product["Packages"] as? [[String: Any]],
                  let package = packages.first(where: { ($0["URL"] as? String)?.hasSuffix("/InstallAssistant.pkg") == true }),
                  let packageURL = trustedURL(package["URL"] as? String),
                  let distributions = product["Distributions"] as? [String: String],
                  let distribution = trustedURL(distributions["English"] ?? distributions["en"] ?? distributions.values.first)
            else { return nil }
            let size = (package["Size"] as? NSNumber)?.doubleValue ?? 0
            return Product(id: id, distribution: distribution, package: packageURL, bytes: size)
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
        let title = capture(#"<title>([^<]+)</title>"#).map(decodeEntities) ?? "macOS \(version)"
        return (title, version, build)
    }

    /// Adds catalog-only installers to the ones softwareupdate offers. Offered entries win, but keep the package as fallback.
    public static func merge(offered: [Installer], catalog: [Installer]) -> [Installer] {
        var result = offered.map { item -> Installer in
            var copy = item; copy.offeredForThisMac = true
            if let match = catalog.first(where: { $0.version == item.version && $0.build == item.build }) {
                copy.packageURL = match.packageURL
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
