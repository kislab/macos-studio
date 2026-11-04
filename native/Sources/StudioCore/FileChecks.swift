import Foundation

public enum Disk {
    /// Free bytes on the volume that holds `path`.
    public static func freeBytes(forPath path: String) -> Int64? {
        (try? FileManager.default.attributesOfFileSystem(forPath: path)[.systemFreeSize] as? NSNumber)?.int64Value
    }
    /// True when the volume at `path` has room for `need` bytes plus a safety margin.
    public static func hasSpace(forPath path: String, need: Int64, margin: Int64 = 2_000_000_000) -> Bool {
        guard let free = freeBytes(forPath: path) else { return true }   // unknown → don't block
        let (needed, overflow) = need.addingReportingOverflow(margin)
        return overflow ? false : free >= needed
    }
}

/// Result of checking a downloaded file against Apple's published size/checksum.
public enum VerifyResult: Equatable, Sendable {
    case ok
    case missing
    case wrongSize(expected: Int64, actual: Int64)
    case wrongChecksum
    case noReference            // Apple publishes no size/checksum to compare against

    public var isGood: Bool { self == .ok }
}

public enum FileVerify {
    /// Pure comparison used by both the IPSW and installer checks (actual values read elsewhere).
    public static func result(actualSize: Int64?, expectedSize: Int64?, actualSHA1: String?, expectedSHA1: String?) -> VerifyResult {
        guard let actualSize else { return .missing }
        if let expectedSize, expectedSize > 0, actualSize != expectedSize {
            return .wrongSize(expected: expectedSize, actual: actualSize)
        }
        if let expectedSHA1, !expectedSHA1.isEmpty {
            guard let actualSHA1 else { return .noReference }
            return actualSHA1.lowercased() == expectedSHA1.lowercased() ? .ok : .wrongChecksum
        }
        return (expectedSize ?? 0) > 0 ? .ok : .noReference
    }
}
