import Foundation

/// A self-made Chrome extension shipped unpacked inside the app. Chrome loads unpacked extensions from a folder
/// ("Entpackte Erweiterung laden"), so the app copies it to a lasting folder and later refreshes that folder in place –
/// Chrome keeps the extension and its saved data as long as the path stays the same.
public struct ChromeExtension: Equatable, Sendable {
    public let folder: URL
    public let name: String
    public let version: String
    public let summary: String

    public init?(folder: URL) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = json["name"] as? String, let version = json["version"] as? String else { return nil }
        self.folder = folder
        self.name = name
        self.version = version
        self.summary = json["description"] as? String ?? ""
    }

    /// All extensions in `directory` (one subfolder each), sorted by name.
    public static func all(in directory: URL) -> [ChromeExtension] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return folders.compactMap { ChromeExtension(folder: $0) }.sorted { $0.name < $1.name }
    }

    /// Version installed in `target`, or nil if the folder holds no (or another) extension.
    public func installedVersion(at target: URL) -> String? {
        guard let installed = ChromeExtension(folder: target), installed.name == name else { return nil }
        return installed.version
    }

    /// Whether `target` holds an older version than this one.
    public func isNewer(than target: URL) -> Bool {
        guard let installed = installedVersion(at: target) else { return false }
        return Self.compare(version, installed) == .orderedDescending
    }

    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    public enum InstallError: LocalizedError {
        case foreignFolder(URL)
        public var errorDescription: String? {
            switch self {
            case .foreignFolder(let url):
                return String(localized: "Der Ordner „\(url.lastPathComponent)“ ist nicht leer und enthält keine Version dieser Erweiterung. Bitte einen leeren Ordner wählen.")
            }
        }
    }

    /// Copies the extension into `target`, replacing an older copy of the same extension in place.
    /// Refuses to touch a non-empty folder that holds something else.
    public func install(to target: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: target.path, isDirectory: &isDir) {
            let contents = (try? fm.contentsOfDirectory(atPath: target.path).filter { !$0.hasPrefix(".") }) ?? []
            guard isDir.boolValue, contents.isEmpty || installedVersion(at: target) != nil else { throw InstallError.foreignFolder(target) }
            for item in contents { try fm.removeItem(at: target.appendingPathComponent(item)) }
        } else {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        }
        for item in try fm.contentsOfDirectory(atPath: folder.path) where !item.hasPrefix(".") {
            try fm.copyItem(at: folder.appendingPathComponent(item), to: target.appendingPathComponent(item))
        }
    }

    /// Writes the extension as a ZIP (files at the top level, like Chrome Web Store uploads expect).
    public func exportZip(to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", folder.path, url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
