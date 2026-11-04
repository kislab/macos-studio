import Foundation

/// Serial numbers made before 2021 (11 or 12 characters) end in a configuration code that Apple's
/// public product lookup resolves to a model name. Since 2021 Apple issues randomized 10-character
/// serials that contain no model information.
public enum SerialLookup {
    public static func normalized(_ query: String) -> String { query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }

    /// Configuration code: last 4 characters of a 12-character serial, last 3 of an 11-character one.
    public static func configCode(for serial: String) -> String? {
        let value = normalized(serial)
        guard value.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else { return nil }
        switch value.count {
        case 12: return String(value.suffix(4))
        case 11: return String(value.suffix(3))
        default: return nil
        }
    }
    public static func isRandomized(_ serial: String) -> Bool { normalized(serial).count == 10 }

    public static func url(for code: String) -> URL? {
        guard code.range(of: "^[A-Z0-9]{3,4}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://support-sp.apple.com/sp/product?cc=\(code)&lang=en_US")
    }

    /// Model name from Apple's answer, e.g. "MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)".
    public static func modelName(fromResponse text: String) -> String? {
        guard let start = text.range(of: "<configCode>"), let end = text.range(of: "</configCode>", range: start.upperBound..<text.endIndex) else { return nil }
        let name = text[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
        return name.isEmpty ? nil : name
    }

    static let families = ["MacBook Pro", "MacBook Air", "MacBook Neo", "MacBook", "iMac Pro", "iMac", "Mac mini", "Mac Studio", "Mac Pro"]

    static func family(of name: String) -> String? { families.first { name.hasPrefix($0) } }
    static func years(in text: String) -> Set<Int> {
        let regex = try! NSRegularExpression(pattern: #"\b(?:19|20)\d\d\b"#)
        let ns = text as NSString
        let found = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { (Int(ns.substring(with: $0.range)) ?? 0, $0.range) }
        var result = Set(found.map(\.0))
        for (a, b) in zip(found, found.dropFirst()) {
            let between = ns.substring(with: NSRange(location: a.1.upperBound, length: b.1.location - a.1.upperBound))
            if between.contains("–") || between.contains("-"), a.0 < b.0, b.0 - a.0 < 10 { result.formUnion(a.0...b.0) }
        }
        return result
    }
    static func chips(in text: String) -> Set<String> {
        let regex = try! NSRegularExpression(pattern: #"\bM\d+\b"#)
        let ns = text as NSString
        return Set(regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) })
    }

    /// Database entries matching Apple's model name: same family and year, same Apple chip or both Intel.
    public static func matches(for appleName: String, in models: [MacModel]) -> [MacModel] {
        guard let family = family(of: appleName) else { return [] }
        let years = years(in: appleName), chips = chips(in: appleName)
        let candidates = models.filter { model in
            guard self.family(of: model.name) == family else { return false }
            let modelYears = self.years(in: model.name).union([model.year])
            guard years.isEmpty || !years.isDisjoint(with: modelYears) else { return false }
            let modelChips = self.chips(in: model.name)
            return chips.isEmpty ? modelChips.isEmpty : !chips.isDisjoint(with: modelChips)
        }
        // Prefer entries naming the same screen size when Apple gives one ("13-inch").
        if let size = appleName.range(of: #"\d+(\.\d+)?(?=-inch)"#, options: .regularExpression).map({ String(appleName[$0]) }) {
            let sized = candidates.filter { $0.name.contains(size + "\"") }
            if !sized.isEmpty { return sized }
        }
        return candidates
    }
}
