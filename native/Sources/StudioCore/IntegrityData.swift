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
            throw failure(String(localized: "Die Installer-App hat ein unbekanntes Format (InstallInfo.plist). Es wurde nichts installiert."))
        }
        guard files["InstallESDDmg.pkg"] != nil, files["BaseSystem.dmg"] != nil else {
            throw failure(String(localized: "Installationsdaten fehlen (InstallESD oder BaseSystem)."))
        }
        for (part, source) in files.sorted(by: { $0.key < $1.key }) {
            guard let name = sharedSupportName(for: part) else { continue }
            let target = support.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: source, to: target)
        }
    }

    /// OS X 10.10 – macOS 10.12 disk images: the expanded InstallOS.pkg / InstallMacOSX.pkg holds the installer
    /// app in its Payload and InstallESD.dmg next to it (its postinstall script would move it into the app).
    public static func diskImageContents(inExpanded folder: URL) -> (app: URL, esd: URL)? {
        var apps: [URL] = [], images: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return nil }
        for case let url as URL in walk {
            if (try? url.resourceValues(forKeys: Set(keys)))?.isSymbolicLink == true { walk.skipDescendants(); continue }
            if url.pathExtension == "app", url.lastPathComponent.hasPrefix("Install "), url.deletingLastPathComponent().lastPathComponent == "Payload" {
                apps.append(url); walk.skipDescendants()
            } else if url.lastPathComponent == "InstallESD.dmg" {
                images.append(url)
            }
        }
        guard apps.count == 1, images.count == 1,
              FileManager.default.isExecutableFile(atPath: apps[0].appendingPathComponent("Contents/Resources/createinstallmedia").path)
        else { return nil }
        return (apps[0], images[0])
    }

    /// Puts InstallESD.dmg into the app's SharedSupport folder (created if missing).
    public static func assemble(app: URL, installESD: URL) throws {
        let support = app.appendingPathComponent("Contents/SharedSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let target = support.appendingPathComponent("InstallESD.dmg")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: installESD, to: target)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)   // as Apple's link_package does
    }

    /// createinstallmedia up to macOS 10.13 offers (and up to 10.12 requires) --applicationpath; from 10.14 on it is deprecated.
    public static func needsApplicationPath(tool: URL) -> Bool {
        guard let data = try? Data(contentsOf: tool, options: .mappedIfSafe) else { return false }
        return data.range(of: Data("--applicationpath, A path".utf8)) != nil
            && data.range(of: Data("\"--applicationpath\" is deprecated".utf8)) == nil
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

    /// Starts the tool once without arguments (createinstallmedia then only prints its usage and changes nothing).
    /// True when macOS kills it at launch: Apple silicon refuses the Apple-signed Intel createinstallmedia of
    /// OS X 10.10 – macOS 10.15 ("Killed: 9"), with or without Rosetta. Intel Macs run it normally.
    public static func killedAtLaunch(_ tool: URL, timeout: TimeInterval = 15) -> Bool {
        let process = Process()
        process.executableURL = tool
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return false }
        if done.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); return false }
        return process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL
    }

    public static let blockedOnAppleSilicon = String(localized: "Auf Macs mit Apple-Chip startet macOS das ältere Apple-Werkzeug createinstallmedia dieses Installers nicht mehr (es wird beim Start sofort beendet) – auch nicht mit Rosetta. Das betrifft OS X 10.10 bis macOS 10.15.\n\nDie Installer-App ist vollständig. Den USB-Stick bitte an einem Mac mit Intel-Prozessor erstellen: Installer-App dorthin kopieren und OS Studio dort verwenden.\n\nDer USB-Stick wurde nicht verändert.")

}
