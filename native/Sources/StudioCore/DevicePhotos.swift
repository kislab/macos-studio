import Foundation

/// Official device photos from Apple's "Identify your iPhone/iPad model" support pages.
/// The app loads them from Apple at launch and keeps them in the user's local cache; nothing is bundled.
public enum DevicePhotos {
    public static let pages = [URL(string: "https://support.apple.com/en-us/108044")!,  // iPhone
                               URL(string: "https://support.apple.com/en-us/108043")!]  // iPad

    /// Normalized model heading → photo URL, e.g. "iphone 16 pro" → https://cdsassets.apple.com/…/iphone-16-pro-colors.png
    public static func parse(html: String) -> [String: URL] {
        guard let regex = try? NSRegularExpression(pattern: #"<h2 class="gb-header">((?:(?!<h2).)*?)</h2>\s*<img class="gb-image"[^>]*?src="([^"]+)""#,
                                                   options: [.dotMatchesLineSeparators]) else { return [:] }
        var result: [String: URL] = [:]
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let heading = normalize(ns.substring(with: match.range(at: 1)))
            guard !heading.isEmpty, result[heading] == nil, let url = trustedURL(ns.substring(with: match.range(at: 2))) else { continue }
            result[heading] = url
        }
        return result
    }

    public static func normalize(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (from, to) in [("&nbsp;", " "), ("\u{00A0}", " "), ("\u{2011}", "-"), ("\u{2010}", "-"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func trustedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              host == "apple.com" || host.hasSuffix(".apple.com"),
              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    /// Apple's English heading for a model identifier, derived from the app's German device name.
    public static func heading(for identifier: String) -> String? {
        let name = DeviceNames.name(for: identifier)
        guard !name.contains("-Modell"), !identifier.hasPrefix("iPod") else { return nil }
        func ordinal(_ n: Int) -> String {
            let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
            return "\(n)\(suffix)"
        }
        func capture(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return nil }
            return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: name).map { String(name[$0]) } }
        }
        var heading = name
        if let m = capture(#"^(iPhone SE|iPad|iPad Air|iPad mini) \((\d+)\. Generation\)$"#), let n = Int(m[1]) {
            heading = "\(m[0]) (\(ordinal(n)) generation)"
        } else if let m = capture(#"^(iPad Pro|iPad Air) \((\d+(?:,\d)?)", (M\d+)\)$"#) {
            heading = "\(m[0]) \(m[1].replacingOccurrences(of: ",", with: "."))-inch (\(m[2]))"
        } else if let m = capture(#"^iPad Pro \((\d+(?:,\d)?)", (\d+)\. Generation\)$"#), let n = Int(m[1]) {
            let size = m[0].replacingOccurrences(of: ",", with: ".")
            heading = n == 1 ? (size == "11" ? "iPad Pro 11-inch" : "iPad Pro (\(size)-inch)") : "iPad Pro \(size)-inch (\(ordinal(n)) generation)"
        } else if let m = capture(#"^iPad Pro \((\d+,\d)"\)$"#) {
            heading = "iPad Pro (\(m[0].replacingOccurrences(of: ",", with: "."))-inch)"
        }
        return normalize(heading)
    }
}
