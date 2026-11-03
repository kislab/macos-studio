import AppKit

/// Keep user-selected locations as bookmarks instead of repeatedly asking for paths.
@MainActor final class SavedFileAccess {
    private var active: [URL] = []
    private(set) var locations: [URL] = []
    init() {
        let saved = UserDefaults.standard.dictionary(forKey: "installerLocationBookmarks") as? [String: Data] ?? [:]
        for data in saved.values {
            var stale = false
            if let url = (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)) ?? (try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)) {
                if url.startAccessingSecurityScopedResource() { active.append(url) }
                locations.append(url)
                if stale { try? remember(url) }
            }
        }
    }
    func remember(_ url: URL) throws {
        let data: Data
        do { data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        var saved = UserDefaults.standard.dictionary(forKey: "installerLocationBookmarks") as? [String: Data] ?? [:]
        saved[url.path] = data
        UserDefaults.standard.set(saved, forKey: "installerLocationBookmarks")
        if !locations.contains(url) {
            locations.append(url)
            if url.startAccessingSecurityScopedResource() { active.append(url) }
        }
    }
    var directories: [String] { locations.filter { $0.pathExtension.lowercased() != "app" }.map(\.path) }
    var installers: [String] { locations.filter { $0.pathExtension.lowercased() == "app" }.map(\.path) }
}
