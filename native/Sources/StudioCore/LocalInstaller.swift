import Foundation
import Darwin

public struct LocalInstaller: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bytes: Int64?
    public let created: Date?
    public let modified: Date?
    public let preparationIssue: String?

    /// Structural preflight only; Apple's tool remains the final integrity check.
    public static func preparationIssue(at path: String) -> String? {
        let app = URL(fileURLWithPath: path).standardizedFileURL
        guard app.pathExtension.lowercased() == "app",
              FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/Resources/createinstallmedia").path) else {
            return "Kein ausführbares createinstallmedia gefunden."
        }
        let support = app.appendingPathComponent("Contents/SharedSupport")
        let payloads = ["SharedSupport.dmg", "InstallESD.dmg", "InstallAssistant.pkg"]
        let present = payloads.contains { name in
            let file = support.appendingPathComponent(name)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isReadableKey]) else { return false }
            return values.isRegularFile == true && values.isReadable == true && (values.fileSize ?? 0) > 0
        }
        guard present else {
            return "Installer unvollständig: In Contents/SharedSupport fehlen lesbare Installationsdaten. Bitte den Installer erneut vollständig laden."
        }
        return nil
    }

    /// Read target OS metadata, never the InstallAssistant application's own version.
    public func matches(_ installer: Installer) -> Bool {
        guard preparationIssue == nil else { return false }
        let support = URL(fileURLWithPath: path).appendingPathComponent("Contents/SharedSupport")
        for filename in ["InstallInfo.plist", "com_apple_MobileAsset_MacSoftwareUpdate.xml"] {
            guard let data = try? Data(contentsOf: support.appendingPathComponent(filename)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            var records = plist["Assets"] as? [[String: Any]] ?? []
            if let info = plist["System Image Info"] as? [String: Any] { records.append(info) }
            for record in records {
                let version = record["OSVersion"] as? String ?? record["version"] as? String
                let build = record["Build"] as? String ?? record["build"] as? String
                if version == installer.version && (installer.build == "Manuell" || build == installer.build) { return true }
            }
        }
        return false
    }

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
                              modified: attributes[.modificationDate] as? Date,
                              preparationIssue: preparationIssue(at: url.path))
    }

    /// Root-owned installers (softwareupdate) cannot be trashed by the user. Instead of moving them into
    /// the privacy-protected ~/.Trash as root (denied for AppleScript admin privileges), hand ownership of
    /// exactly the confirmed bundle to the user; the app then trashes it normally and recoverably.
    public func authorizedOwnershipCommand(owner: uid_t) throws -> String {
        guard Self.inspect(path) == self else {
            throw NSError(domain: "LocalInstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: "Der Installer wurde verändert oder ist nicht mehr vorhanden. Bitte die Liste aktualisieren."])
        }
        let source = shellQuote(path)
        return "test ! -L " + source + " && test -d " + source + " && /usr/sbin/chown -R -P " + String(owner) + " " + source
    }

    /// Revalidate the exact bundle shown in the confirmation before moving it.
    public func moveToTrash() throws {
        guard let current = Self.inspect(path), current == self else {
            throw NSError(domain: "LocalInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "Der Installer wurde verändert oder ist nicht mehr vorhanden. Bitte die Liste aktualisieren."])
        }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}
