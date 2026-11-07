import Foundation
import StudioCore

extension Notification.Name {
    /// Posted after names of new iPhones/iPads were learned, so lists showing device names redraw.
    static let devicesLearned = Notification.Name("OSStudioDevicesLearned")
}

/// Looks for iPhones, iPads and Macs newer than this app version: compares Apple's device and macOS lists
/// with the built-in tables and asks AppleDB only about identifiers the app does not know. Results are cached
/// on this Mac; the check runs at most once a day (or on request) and can be turned off in Settings.
@MainActor final class DeviceDiscoveryStore: ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: AppSettings.discoveryKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: AppSettings.discoveryKey) }
    }
    @Published private(set) var running = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    /// Devices found automatically so far (names), newest check first.
    @Published private(set) var discoveredNames: [String] = []
    @Published private(set) var macModels: [MacModel] = []

    private struct Cache: Codable {
        var checked: Date?
        var records: [String: DeviceDiscovery.Record] = [:]
        var macVersions: [String: String] = [:]
        var misses: [String: Date] = [:]
    }
    private var cache = Cache()
    private let builtInMacs: Set<String>
    private static var file: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.appletools.macosstudio/DeviceDiscovery.json")
    }

    init(builtInMacs: Set<String>) {
        self.builtInMacs = builtInMacs
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode(Cache.self, from: data) { cache = saved }
        apply()
    }

    /// Checks Apple's lists (at most daily unless `force`) and looks up unknown identifiers.
    func refresh(force: Bool = false) async {
        guard enabled, !running else { return }
        if !force, let checked = cache.checked, Date().timeIntervalSince(checked) < 24 * 3600 { return }
        running = true; lastError = nil
        defer { running = false }
        async let mobileData = Self.fetch(FirmwareCatalog.url)
        async let macData = Self.fetch(DeviceDiscovery.macRestoreFeed)
        let (mobileList, macList) = await (mobileData, macData)
        guard let mobileList, let macList else {
            lastError = String(localized: "Apples Gerätelisten sind gerade nicht erreichbar."); return
        }
        let mobile = DeviceDiscovery.mobileIdentifiers(fromDeviceList: (try? Gzip.decompress(mobileList)) ?? mobileList)
        let macs = DeviceDiscovery.macs(fromRestoreFeed: (try? Gzip.decompress(macList)) ?? macList)
        guard !mobile.isEmpty, !macs.isEmpty else { lastError = String(localized: "Apples Gerätelisten sind unlesbar."); return }
        for (id, version) in macs where !builtInMacs.contains(id) { cache.macVersions[id] = version }
        let unknown = (mobile.filter { !DeviceNames.isBuiltIn($0) } + macs.keys.filter { !builtInMacs.contains($0) })
            .filter { cache.records[$0] == nil && (cache.misses[$0].map { Date().timeIntervalSince($0) > 7 * 24 * 3600 } ?? true) }
            .sorted().prefix(40)
        let found = await Self.lookUp(Array(unknown))
        for id in unknown {
            if let record = found[id] { cache.records[id] = record; cache.misses[id] = nil } else { cache.misses[id] = Date() }
        }
        cache.checked = Date()
        save(); apply()
    }

    /// "Meinen Mac erkennen" on a Mac newer than the database: look this one identifier up right away.
    func resolveMac(_ identifier: String) async -> MacModel? {
        guard enabled, DeviceDiscovery.isMac(identifier) else { return nil }
        if cache.records[identifier] == nil || cache.macVersions[identifier] == nil {
            if cache.macVersions[identifier] == nil, let data = await Self.fetch(DeviceDiscovery.macRestoreFeed),
               let version = DeviceDiscovery.macs(fromRestoreFeed: (try? Gzip.decompress(data)) ?? data)[identifier] {
                cache.macVersions[identifier] = version
            }
            if cache.records[identifier] == nil, let record = await Self.lookUp([identifier])[identifier] { cache.records[identifier] = record }
            save(); apply()
        }
        return macModels.first { $0.identifiers.contains(identifier) }
    }

    private func apply() {
        lastChecked = cache.checked
        var names: [String: String] = [:]
        for (id, record) in cache.records where !DeviceDiscovery.isMac(id) { names[id] = DeviceDiscovery.displayName(record) }
        DeviceNames.learn(names)
        // Variants with the same name (e.g. Wi-Fi and Cellular) become one entry, like the built-in database.
        var grouped: [String: MacModel] = [:]
        for (id, record) in cache.records.sorted(by: { $0.key < $1.key }) where DeviceDiscovery.isMac(id) && !builtInMacs.contains(id) {
            guard let version = cache.macVersions[id] else { continue }
            let model = DeviceDiscovery.macModel(identifier: id, record: record, newestMacOS: version)
            if let existing = grouped[model.name] {
                grouped[model.name] = MacModel(name: existing.name, category: existing.category, year: existing.year,
                                               identifiers: existing.identifiers + [id], model_numbers: (existing.model_numbers ?? []) + (model.model_numbers ?? []),
                                               cpu: existing.cpu, hw_icon: existing.hw_icon, arch: existing.arch, min_macos: existing.min_macos,
                                               max_macos: existing.max_macos, supported_versions: existing.supported_versions, notes: existing.notes)
            } else { grouped[model.name] = model }
        }
        macModels = grouped.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        discoveredNames = Array(Set(names.values).union(macModels.map(\.name))).sorted()
        NotificationCenter.default.post(name: .devicesLearned, object: nil)
    }

    /// Forgets everything found automatically (used by "Alle Einstellungen zurücksetzen").
    func clear() {
        cache = Cache(); try? FileManager.default.removeItem(at: Self.file); apply()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: Self.file, options: .atomic) }
    }

    private nonisolated static func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// AppleDB records for these identifiers, four requests at a time. Missing ones are simply left out.
    private nonisolated static func lookUp(_ identifiers: [String]) async -> [String: DeviceDiscovery.Record] {
        await withTaskGroup(of: (String, DeviceDiscovery.Record?).self) { group in
            var result: [String: DeviceDiscovery.Record] = [:]
            var pending = identifiers.makeIterator()
            func next() {
                guard let id = pending.next(), let url = DeviceDiscovery.appleDBURL(for: id) else { return }
                group.addTask { (id, await fetch(url).flatMap { DeviceDiscovery.record(fromAppleDB: $0, identifier: id) }) }
            }
            for _ in 0..<4 { next() }
            for await (id, record) in group {
                if let record { result[id] = record }
                next()
            }
            return result
        }
    }
}
