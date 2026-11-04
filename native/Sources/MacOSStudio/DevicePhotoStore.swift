import AppKit
import StudioCore

/// Loads Apple's official device photos at launch and keeps them in ~/Library/Caches. Shown offline from the cache;
/// the pages are checked again after a week. Nothing is bundled with the app.
@MainActor final class DevicePhotoStore: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var loading = false
    @Published private(set) var loaded = 0
    @Published private(set) var total = 0
    @Published var enabled = UserDefaults.standard.object(forKey: AppSettings.photosKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: AppSettings.photosKey)
            revision += 1
            if enabled { Task { await refresh() } }
        }
    }
    var cacheBytes: Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    func clearCache() {
        try? FileManager.default.removeItem(at: folder)
        index = [:]; images = [:]; revision += 1
        if enabled { Task { await refresh() } }
    }
    private var index: [String: String] = [:]          // normalized heading → cached file name
    private var images: [String: NSImage] = [:]
    private var refreshing = false
    private let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.appletools.macosstudio/DevicePhotos", isDirectory: true)
    private var indexFile: URL { folder.appendingPathComponent("index.json") }

    init() {
        if let data = try? Data(contentsOf: indexFile), let saved = try? JSONDecoder().decode([String: String].self, from: data) { index = saved }
    }

    func image(for identifier: String) -> NSImage? {
        guard enabled, let heading = DevicePhotos.heading(for: identifier), let file = index[heading] else { return nil }
        if let cached = images[file] { return cached }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(file)) else { return nil }
        images[file] = image
        return image
    }

    func refresh() async {
        guard enabled, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        let age = (try? indexFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) } ?? .infinity
        let folder = folder
        var photos: [String: URL] = [:]
        if age > 7 * 24 * 3600 || index.isEmpty {
            for page in DevicePhotos.pages {
                var request = URLRequest(url: page, timeoutInterval: 30)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) OS-Studio", forHTTPHeaderField: "User-Agent")
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                photos.merge(DevicePhotos.parse(html: String(decoding: data, as: UTF8.self))) { first, _ in first }
            }
        }
        guard !photos.isEmpty else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let toLoad = photos.filter { !FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.value.deletingLastPathComponent().lastPathComponent + "-" + $0.value.lastPathComponent).path) }
        if !toLoad.isEmpty { loading = true; loaded = 0; total = toLoad.count }
        defer { loading = false }
        let downloaded = await withTaskGroup(of: (heading: String, name: String, new: Bool)?.self) { group -> [String: String] in
            var pending = Array(photos), result: [String: String] = [:]
            func next() {
                guard let (heading, url) = pending.popLast() else { return }
                group.addTask {
                    let name = url.deletingLastPathComponent().lastPathComponent + "-" + url.lastPathComponent
                    let target = folder.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: target.path) { return (heading, name, false) }
                    guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 60)),
                          (response as? HTTPURLResponse)?.statusCode == 200, NSImage(data: data) != nil,
                          (try? data.write(to: target, options: .atomic)) != nil else { return nil }
                    return (heading, name, true)
                }
            }
            for _ in 0..<6 { next() }
            while let item = await group.next() {
                if let item {
                    result[item.heading] = item.name
                    if item.new { await MainActor.run { if self.total > 0 { self.loaded += 1 } } }
                }
                next()
            }
            return result
        }
        guard !downloaded.isEmpty else { return }
        index.merge(downloaded) { _, new in new }
        images.removeAll()
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: indexFile, options: .atomic) }
        revision += 1
    }
}
