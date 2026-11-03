import Foundation

public struct LocalInstaller: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bytes: Int64?
    public let created: Date?
    public let modified: Date?

    public static func discover(roots: [String], known: [String]) -> [LocalInstaller] {
        var paths = Set(known)
        for root in roots {
            let url = URL(fileURLWithPath: root)
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let entry as URL in enumerator {
                if entry.pathExtension.lowercased() == "app" { paths.insert(entry.path) }
            }
        }
        var unique: [String: LocalInstaller] = [:]
        for path in paths {
            if let item = Self.inspect(path) { unique[item.path] = item }
        }
        return unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func inspect(_ path: String) -> LocalInstaller? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension.lowercased() == "app",
              url.resolvingSymlinksInPath().path == url.path,
              FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/Resources/createinstallmedia").path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeDirectory else { return nil }
        var bytes: Int64 = 0
        var complete = true
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in complete = false; return true }) {
            for case let file as URL in enumerator {
                guard let values = try? file.resourceValues(forKeys: Set(keys)) else { complete = false; continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
        } else { complete = false }
        return LocalInstaller(path: url.path, name: url.deletingPathExtension().lastPathComponent,
                              bytes: complete ? bytes : nil,
                              created: attributes[.creationDate] as? Date,
                              modified: attributes[.modificationDate] as? Date)
    }

    /// Revalidate the exact bundle shown in the confirmation before moving it.
    public func moveToTrash() throws {
        guard let current = Self.inspect(path), current == self else {
            throw NSError(domain: "LocalInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "Der Installer wurde verändert oder ist nicht mehr vorhanden. Bitte die Liste aktualisieren."])
        }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}
