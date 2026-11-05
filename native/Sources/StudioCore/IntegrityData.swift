import CryptoKit
import Foundation

/// Apple's chunk lists ("CNKL"): the `.integrityDataV1` files next to catalog packages and the `.chunklist`
/// files of BaseSystem/AppleDiagnostics. A list of (chunk size, SHA-256) covering the whole file.
public struct Chunklist: Equatable, Sendable {
    public struct Chunk: Equatable, Sendable {
        public let size: UInt32
        public let sha256: Data
    }
    public let chunks: [Chunk]
    public var totalBytes: Int64 { chunks.reduce(0) { $0 + Int64($1.size) } }

    /// Parses the binary format; rejects anything malformed or using an unknown hash method.
    public static func parse(_ data: Data) -> Chunklist? {
        let bytes = [UInt8](data)
        guard bytes.count >= 36, bytes[0..<4] == [0x43, 0x4E, 0x4B, 0x4C] else { return nil }   // "CNKL"
        func u32(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[at + $1]) << (8 * UInt32($1)) } }
        func u64(_ at: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(bytes[at + $1]) << (8 * UInt64($1)) } }
        let headerSize = u32(4), chunkMethod = bytes[9]
        let count = u64(12), offset = u64(20)
        guard headerSize == 36, chunkMethod == 1, count > 0, count < 10_000_000, offset >= 36,
              offset + count * 36 <= UInt64(bytes.count) else { return nil }
        var chunks: [Chunk] = []
        chunks.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let start = Int(offset) + index * 36
            let size = u32(start)
            guard size > 0 else { return nil }
            chunks.append(Chunk(size: size, sha256: Data(bytes[(start + 4)..<(start + 36)])))
        }
        return Chunklist(chunks: chunks)
    }

    public enum Outcome: Equatable, Sendable { case ok, wrongSize(expected: Int64, actual: Int64), mismatch(chunk: Int) }

    /// Hashes `file` chunk by chunk. `progress` receives 0…1.
    public func verify(_ file: URL, isCancelled: () -> Bool = { false }, progress: (Double) -> Void = { _ in }) throws -> Outcome {
        let actual = ((try FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? NSNumber)?.int64Value ?? -1
        guard actual == totalBytes else { return .wrongSize(expected: totalBytes, actual: actual) }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var done: Int64 = 0
        for (index, chunk) in chunks.enumerated() {
            if isCancelled() { throw CancellationError() }
            guard let data = try handle.read(upToCount: Int(chunk.size)), data.count == Int(chunk.size),
                  Data(SHA256.hash(data: data)) == chunk.sha256 else { return .mismatch(chunk: index) }
            done += Int64(chunk.size)
            progress(Double(done) / Double(totalBytes))
        }
        return .ok
    }
}

/// macOS 10.13–10.15 from Apple's catalog: InstallAssistantAuto.pkg carries "Install macOS ….app" without
/// installation data. The downloaded images go into its SharedSupport folder under the names the app's
/// own InstallInfo.plist expects (InstallESDDmg.pkg is the InstallESD.dmg).
public enum LegacyInstaller {
    public static func sharedSupportName(for part: String) -> String? {
        switch part {
        case "InstallESDDmg.pkg": return "InstallESD.dmg"
        case "BaseSystem.dmg", "BaseSystem.chunklist", "AppleDiagnostics.dmg", "AppleDiagnostics.chunklist": return part
        default: return nil
        }
    }

    /// The single "Install macOS ….app" inside an expanded (pkgutil --expand-full) InstallAssistantAuto.pkg.
    public static func stubApp(inExpanded folder: URL) -> URL? {
        let payload = folder.appendingPathComponent("Payload")
        let apps = ((try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" && $0.lastPathComponent.hasPrefix("Install ") }
        guard apps.count == 1,
              FileManager.default.isExecutableFile(atPath: apps[0].appendingPathComponent("Contents/Resources/createinstallmedia").path)
        else { return nil }
        return apps[0]
    }

    /// Moves the downloaded files into the app. Refuses when the app does not expect InstallESD.dmg.
    public static func assemble(app: URL, files: [String: URL]) throws {
        let support = app.appendingPathComponent("Contents/SharedSupport")
        let info = support.appendingPathComponent("InstallInfo.plist")
        guard let data = try? Data(contentsOf: info),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              (plist["Payload Image Info"] as? [String: Any])?["URL"] as? String == "InstallESD.dmg" else {
            throw failure("Die Installer-App hat ein unbekanntes Format (InstallInfo.plist). Es wurde nichts installiert.")
        }
        guard files["InstallESDDmg.pkg"] != nil, files["BaseSystem.dmg"] != nil else {
            throw failure("Installationsdaten fehlen (InstallESD oder BaseSystem).")
        }
        for (part, source) in files.sorted(by: { $0.key < $1.key }) {
            guard let name = sharedSupportName(for: part) else { continue }
            let target = support.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: source, to: target)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "LegacyInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// CPU architectures inside a Mach-O executable (thin or universal).
public enum MachO {
    public static func architectures(of url: URL) -> Set<String> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096) else { return [] }
        return architectures(header: data)
    }

    public static func architectures(header data: Data) -> Set<String> {
        let b = [UInt8](data)
        guard b.count >= 8 else { return [] }
        func be(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(b[at + $1]) } }
        func le(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[at + $1]) << (8 * UInt32($1)) } }
        func name(_ cpu: UInt32) -> String? { cpu == 0x0100_0007 ? "x86_64" : cpu == 0x0100_000C ? "arm64" : nil }
        switch be(0) {
        case 0xCAFE_BABE:                                       // universal, big-endian header
            let count = Int(be(4))
            guard count > 0, count < 20, b.count >= 8 + count * 20 else { return [] }
            return Set((0..<count).compactMap { name(be(8 + $0 * 20)) })
        case 0xCFFA_EDFE:                                       // thin 64-bit, little-endian
            return Set([name(le(4))].compactMap { $0 })
        default:
            return []
        }
    }

    /// German hint when an Intel-only tool cannot run on this Apple-silicon Mac (Rosetta missing).
    public static func rosettaIssue(executable: URL, hostIsARM: Bool, rosettaInstalled: Bool) -> String? {
        guard hostIsARM, !rosettaInstalled else { return nil }
        let archs = architectures(of: executable)
        guard !archs.isEmpty, !archs.contains("arm64") else { return nil }
        return "Dieser ältere Installer enthält nur ein Intel-Programm (createinstallmedia). Auf diesem Mac wird dafür Rosetta benötigt.\n\nRosetta im Terminal installieren:\nsoftwareupdate --install-rosetta --agree-to-license\n\nDer USB-Stick wurde nicht verändert."
    }
}
