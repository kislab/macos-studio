import Foundation

/// Marketing names for iPhone, iPad and iPod touch model identifiers. Unknown identifiers stay as they are.
public enum DeviceNames {
    public static func name(for identifier: String) -> String {
        if let name = table[identifier] ?? learned(identifier) { return name }
        for family in ["iPhone", "iPad", "iPod"] where identifier.hasPrefix(family) { return "\(family)-Modell \(identifier)" }
        return identifier
    }

    /// True when the built-in table knows this identifier.
    public static func isBuiltIn(_ identifier: String) -> Bool { table[identifier] != nil }

    /// Names found at runtime for devices newer than this app (see DeviceDiscovery). Built-in names win.
    public static func learn(_ names: [String: String]) {
        learnedLock.lock(); learnedNames.merge(names) { _, new in new }; learnedLock.unlock()
    }
    private static func learned(_ identifier: String) -> String? {
        learnedLock.lock(); defer { learnedLock.unlock() }; return learnedNames[identifier]
    }
    private static let learnedLock = NSLock()
    nonisolated(unsafe) private static var learnedNames: [String: String] = [:]

    public enum Family: Int, CaseIterable, Sendable { case iPhone, iPad, iPod
        public var title: String { switch self { case .iPhone: "iPhone"; case .iPad: "iPad"; case .iPod: "iPod touch" } }
    }
    public static func family(of identifier: String) -> Family {
        identifier.hasPrefix("iPhone") ? .iPhone : identifier.hasPrefix("iPad") ? .iPad : .iPod
    }

    /// Physical design, used to pick a matching device symbol.
    public enum Design: Sendable { case homeButton, notch, dynamicIsland, padHomeButton, padFullScreen, pod }
    public static func design(of identifier: String) -> Design {
        let parts = identifier.drop { !$0.isNumber }.split(separator: ",").compactMap { Int($0) }
        let major = parts.first ?? 0, minor = parts.count > 1 ? parts[1] : 0
        switch family(of: identifier) {
        case .iPod: return .pod
        case .iPhone:
            if identifier == "iPhone12,8" || identifier == "iPhone14,6" { return .homeButton }      // SE 2 & 3
            if identifier == "iPhone17,5" { return .notch }                                         // 16e
            if major < 10 || (major == 10 && [1, 2, 4, 5].contains(minor)) { return .homeButton }
            if major >= 16 || (major == 15 && minor >= 2) { return .dynamicIsland }
            return .notch
        case .iPad:
            let fullScreen: Set<String> = ["iPad13,18", "iPad13,19", "iPad15,7", "iPad15,8", "iPad14,1", "iPad14,2"]
            if fullScreen.contains(identifier) || major == 8 || (major == 13 && minor != 18 && minor != 19) || major >= 14 { return .padFullScreen }
            return .padHomeButton
        }
    }

    /// List order: family (iPhone, iPad, iPod touch), then newest model first (iPhone13,2 = iPhone 12 before iPhone12,1 = iPhone 11).
    public static func newestFirst(_ a: String, _ b: String) -> Bool {
        let fa = family(of: a), fb = family(of: b)
        return fa == fb ? order(b, a) : fa.rawValue < fb.rawValue
    }

    /// Sort by family, then by numeric generation (iPhone17,1 after iPhone9,1).
    public static func order(_ a: String, _ b: String) -> Bool { a.compare(b, options: .numeric) == .orderedAscending }

    static let table: [String: String] = {
        var names: [String: String] = [:]
        func set(_ name: String, _ ids: String...) { for id in ids { names[id] = name } }
        // iPhone
        set("iPhone", "iPhone1,1"); set("iPhone 3G", "iPhone1,2"); set("iPhone 3GS", "iPhone2,1")
        set("iPhone 4", "iPhone3,1", "iPhone3,2", "iPhone3,3"); set("iPhone 4s", "iPhone4,1")
        set("iPhone 5", "iPhone5,1", "iPhone5,2"); set("iPhone 5c", "iPhone5,3", "iPhone5,4"); set("iPhone 5s", "iPhone6,1", "iPhone6,2")
        set("iPhone 6", "iPhone7,2"); set("iPhone 6 Plus", "iPhone7,1"); set("iPhone 6s", "iPhone8,1"); set("iPhone 6s Plus", "iPhone8,2")
        set("iPhone SE (1. Generation)", "iPhone8,4"); set("iPhone 7", "iPhone9,1", "iPhone9,3"); set("iPhone 7 Plus", "iPhone9,2", "iPhone9,4")
        set("iPhone 8", "iPhone10,1", "iPhone10,4"); set("iPhone 8 Plus", "iPhone10,2", "iPhone10,5"); set("iPhone X", "iPhone10,3", "iPhone10,6")
        set("iPhone XS", "iPhone11,2"); set("iPhone XS Max", "iPhone11,4", "iPhone11,6"); set("iPhone XR", "iPhone11,8")
        set("iPhone 11", "iPhone12,1"); set("iPhone 11 Pro", "iPhone12,3"); set("iPhone 11 Pro Max", "iPhone12,5"); set("iPhone SE (2. Generation)", "iPhone12,8")
        set("iPhone 12 mini", "iPhone13,1"); set("iPhone 12", "iPhone13,2"); set("iPhone 12 Pro", "iPhone13,3"); set("iPhone 12 Pro Max", "iPhone13,4")
        set("iPhone 13 mini", "iPhone14,4"); set("iPhone 13", "iPhone14,5"); set("iPhone 13 Pro", "iPhone14,2"); set("iPhone 13 Pro Max", "iPhone14,3")
        set("iPhone SE (3. Generation)", "iPhone14,6"); set("iPhone 14", "iPhone14,7"); set("iPhone 14 Plus", "iPhone14,8")
        set("iPhone 14 Pro", "iPhone15,2"); set("iPhone 14 Pro Max", "iPhone15,3"); set("iPhone 15", "iPhone15,4"); set("iPhone 15 Plus", "iPhone15,5")
        set("iPhone 15 Pro", "iPhone16,1"); set("iPhone 15 Pro Max", "iPhone16,2"); set("iPhone 16", "iPhone17,3"); set("iPhone 16 Plus", "iPhone17,4")
        set("iPhone 16 Pro", "iPhone17,1"); set("iPhone 16 Pro Max", "iPhone17,2"); set("iPhone 16e", "iPhone17,5")
        set("iPhone 17 Pro", "iPhone18,1"); set("iPhone 17 Pro Max", "iPhone18,2"); set("iPhone 17", "iPhone18,3"); set("iPhone Air", "iPhone18,4")
        set("iPhone 17e", "iPhone18,5")
        set("iPhone 18 Pro", "iPhone19,2"); set("iPhone 18 Pro Max", "iPhone19,3", "iPhone19,7"); set("iPhone Duo", "iPhone19,4")
        // iPod touch
        set("iPod touch (1. Generation)", "iPod1,1"); set("iPod touch (2. Generation)", "iPod2,1"); set("iPod touch (3. Generation)", "iPod3,1")
        set("iPod touch (4. Generation)", "iPod4,1"); set("iPod touch (5. Generation)", "iPod5,1"); set("iPod touch (6. Generation)", "iPod7,1"); set("iPod touch (7. Generation)", "iPod9,1")
        // iPad
        set("iPad", "iPad1,1"); set("iPad 2", "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4"); set("iPad mini", "iPad2,5", "iPad2,6", "iPad2,7")
        set("iPad (3. Generation)", "iPad3,1", "iPad3,2", "iPad3,3"); set("iPad (4. Generation)", "iPad3,4", "iPad3,5", "iPad3,6")
        set("iPad Air", "iPad4,1", "iPad4,2", "iPad4,3"); set("iPad mini 2", "iPad4,4", "iPad4,5", "iPad4,6"); set("iPad mini 3", "iPad4,7", "iPad4,8", "iPad4,9")
        set("iPad mini 4", "iPad5,1", "iPad5,2"); set("iPad Air 2", "iPad5,3", "iPad5,4"); set("iPad Pro (9,7\")", "iPad6,3", "iPad6,4")
        set("iPad Pro (12,9\", 1. Generation)", "iPad6,7", "iPad6,8"); set("iPad (5. Generation)", "iPad6,11", "iPad6,12")
        set("iPad Pro (12,9\", 2. Generation)", "iPad7,1", "iPad7,2"); set("iPad Pro (10,5\")", "iPad7,3", "iPad7,4"); set("iPad (6. Generation)", "iPad7,5", "iPad7,6")
        set("iPad (7. Generation)", "iPad7,11", "iPad7,12"); set("iPad Pro (11\", 1. Generation)", "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4")
        set("iPad Pro (12,9\", 3. Generation)", "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8"); set("iPad Pro (11\", 2. Generation)", "iPad8,9", "iPad8,10")
        set("iPad Pro (12,9\", 4. Generation)", "iPad8,11", "iPad8,12"); set("iPad mini (5. Generation)", "iPad11,1", "iPad11,2")
        set("iPad Air (3. Generation)", "iPad11,3", "iPad11,4"); set("iPad (8. Generation)", "iPad11,6", "iPad11,7"); set("iPad (9. Generation)", "iPad12,1", "iPad12,2")
        set("iPad Air (4. Generation)", "iPad13,1", "iPad13,2"); set("iPad Pro (11\", 3. Generation)", "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7")
        set("iPad Pro (12,9\", 5. Generation)", "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11"); set("iPad Air (5. Generation)", "iPad13,16", "iPad13,17")
        set("iPad (10. Generation)", "iPad13,18", "iPad13,19"); set("iPad mini (6. Generation)", "iPad14,1", "iPad14,2")
        set("iPad Pro (11\", 4. Generation)", "iPad14,3", "iPad14,4"); set("iPad Pro (12,9\", 6. Generation)", "iPad14,5", "iPad14,6")
        set("iPad Air (11\", M2)", "iPad14,8", "iPad14,9"); set("iPad Air (13\", M2)", "iPad14,10", "iPad14,11")
        set("iPad Air (11\", M3)", "iPad15,3", "iPad15,4"); set("iPad Air (13\", M3)", "iPad15,5", "iPad15,6"); set("iPad (A16)", "iPad15,7", "iPad15,8")
        set("iPad mini (A17 Pro)", "iPad16,1", "iPad16,2"); set("iPad Pro (11\", M4)", "iPad16,3", "iPad16,4"); set("iPad Pro (13\", M4)", "iPad16,5", "iPad16,6")
        set("iPad Air (11\", M4)", "iPad16,8", "iPad16,9"); set("iPad Air (13\", M4)", "iPad16,10", "iPad16,11")
        set("iPad Pro (11\", M5)", "iPad17,1", "iPad17,2"); set("iPad Pro (13\", M5)", "iPad17,3", "iPad17,4")
        set("iPad mini (A20 Pro)", "iPad19,1", "iPad19,2")
        return names
    }()
}
