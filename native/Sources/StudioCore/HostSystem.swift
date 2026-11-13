import Foundation

/// How a catalog installer relates to the macOS running on this Mac.
public enum HostRelation: Equatable, Sendable {
    /// Exactly this build runs on this Mac.
    case installed
    /// Same version number, but a build Apple made for other hardware.
    case sameVersion
    /// This Mac already runs a newer version.
    case olderThanHost
    /// Newer than this Mac, or not comparable.
    case other
}

public enum HostSystem {
    /// Version of the running macOS, e.g. "27.2.1".
    public static var version: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion == 0 ? "\(v.majorVersion).\(v.minorVersion)" : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Build of the running macOS, e.g. "26B131".
    public static var build: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }

    public static func relation(version: String, build: String, hostVersion: String = version, hostBuild: String = build) -> HostRelation {
        if !hostBuild.isEmpty, build.caseInsensitiveCompare(hostBuild) == .orderedSame { return .installed }
        guard let mine = numbers(version), let host = numbers(hostVersion) else { return .other }
        switch compare(mine, host) {
        case .orderedSame: return .sameVersion
        case .orderedAscending: return .olderThanHost
        case .orderedDescending: return .other
        }
    }

    private static func numbers(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.map { $0! }
    }

    private static func compare(_ a: [Int], _ b: [Int]) -> ComparisonResult {
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
