import AppKit
import SwiftUI
import StudioCore

/// iPhone & iPad: lists the current IPSW restore images from Apple's device software list and downloads
/// them to ~/Downloads. Download only – nothing is written to a device.
@MainActor final class FirmwareStore: ObservableObject {
    @Published var items: [Firmware] = []
    @Published var query = ""
    @Published var loading = false
    @Published var status = "Apple-Liste noch nicht geladen"
    @Published var active: Firmware?
    @Published var progress: Double?
    @Published var written: Double = 0
    @Published var expected: Double = 0
    @Published var mbits: Double?
    @Published var phase = ""
    @Published var finished: URL?
    @Published var error: String?
    private var download: PackageDownload?
    private var sample: (time: TimeInterval, bytes: Int64) = (0, 0)
    private var cancelled = false

    var visible: [Firmware] { query.isEmpty ? items : items.filter { $0.matches(query: query) } }
    var downloading: Bool { active != nil && finished == nil }

    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }
    /// Save folder for IPSW files: Downloads by default, or the folder the user picked (remembered).
    @Published private(set) var folder: URL = FirmwareStore.savedFolder()
    private static let folderKey = "firmwareFolder"
    private static func savedFolder() -> URL {
        var isDirectory: ObjCBool = false
        if let path = UserDefaults.standard.string(forKey: folderKey),
           FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return downloads
    }
    var usesDownloads: Bool { folder.standardizedFileURL.path == Self.downloads.standardizedFileURL.path }
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Hier speichern"
        panel.message = "Ordner für iPhone-, iPad- und iPod-Firmware (IPSW) wählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            error = "In diesen Ordner kann OS Studio nicht schreiben:\n\(url.path)\nBitte einen anderen Ordner wählen."; return
        }
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
    }
    func resetFolder() {
        folder = Self.downloads
        UserDefaults.standard.removeObject(forKey: Self.folderKey)
    }
    func existing(_ item: Firmware) -> URL? {
        let url = folder.appendingPathComponent(item.fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func load() async {
        guard !loading else { return }
        loading = true; status = "Apple-Liste wird geladen …"
        defer { loading = false }
        do {
            var request = URLRequest(url: FirmwareCatalog.url, timeoutInterval: 60)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Apple-Liste nicht erreichbar.") }
            let parsed = await Task.detached(priority: .userInitiated) { FirmwareCatalog.parse((try? Gzip.decompress(data)) ?? data) }.value
            guard !parsed.isEmpty else { throw failure("Apple-Liste enthält keine Firmware.") }
            items = parsed
            status = "\(parsed.count) aktuelle Firmware-Dateien · direkt von Apple (updates.cdn-apple.com)"
        } catch {
            status = "Liste konnte nicht geladen werden"; self.error = error.localizedDescription
        }
    }

    func start(_ item: Firmware, studio: StudioModel) async {
        guard !downloading, !studio.busy, !studio.loading else { return }
        if let file = existing(item) {
            error = "\(item.fileName) liegt bereits im gewählten Ordner.\n\(file.path)"
            NSWorkspace.shared.activateFileViewerSelecting([file]); return
        }
        studio.busy = true
        defer { studio.busy = false; download = nil; mbits = nil }
        active = item; finished = nil; progress = 0; written = 0; expected = 0; cancelled = false
        phase = "IPSW wird geladen"
        let destination = folder
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            error = "In den gewählten Ordner kann nicht geschrieben werden:\n\(destination.path)\nBitte unter „Speicherort“ einen anderen Ordner wählen."
            active = nil; progress = nil; return
        }
        let target = destination.appendingPathComponent(item.fileName)
        let partial = destination.appendingPathComponent(item.fileName + ".download")
        let downloader = PackageDownload(); download = downloader
        sample = (ProcessInfo.processInfo.systemUptime, 0)
        do {
            _ = try await downloader.run(item.url, to: partial) { [weak self] written, expected in
                Task { @MainActor in self?.report(written: written, expected: expected) }
            }
            mbits = nil
            if let sha1 = item.sha1 {
                phase = "Prüfsumme wird geprüft …"; progress = nil
                let actual = try await Task.detached(priority: .userInitiated) { try FirmwareCatalog.sha1(of: partial) }.value
                guard actual == sha1 else {
                    try? FileManager.default.removeItem(at: partial)
                    throw failure("Die Prüfsumme stimmt nicht mit Apples Angabe überein. Die Datei wurde gelöscht; bitte erneut laden.")
                }
            }
            try FileManager.default.moveItem(at: partial, to: target)
            finished = target; progress = 100
            let place = destination.lastPathComponent
            phase = item.sha1 == nil ? "Fertig · gespeichert in „\(place)“" : "Fertig · Prüfsumme bestätigt · gespeichert in „\(place)“"
        } catch {
            try? FileManager.default.removeItem(at: partial)
            active = nil; progress = nil
            if cancelled || (error as? URLError)?.code == .cancelled { phase = ""; return }
            self.error = "Download fehlgeschlagen.\n\(error.localizedDescription)"
        }
    }
    func cancel() { cancelled = true; download?.cancel() }
    func dismiss() { active = nil; finished = nil; progress = nil; phase = "" }

    private func report(written: Int64, expected: Int64) {
        guard downloading else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - sample.time >= 1 else { return }
        mbits = Double(written - sample.bytes) * 8 / (now - sample.time) / 1_000_000
        sample = (now, written)
        self.written = Double(written); self.expected = Double(max(expected, 0))
        progress = expected > 0 ? Double(written) / Double(expected) * 100 : nil
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "OSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

struct FirmwareView: View {
    @ObservedObject var store: FirmwareStore
    @ObservedObject var studio: StudioModel
    @ObservedObject var photos: DevicePhotoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("iPhone & iPad").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Aktuelle Firmware (IPSW) direkt von Apple laden. Es wird nur heruntergeladen – kein Gerät wird verändert.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label {
                    Text("Speicherort: ").foregroundColor(.secondary) + Text(store.usesDownloads ? "Downloads" : store.folder.path)
                } icon: { Image(systemName: "folder") }
                .lineLimit(1).truncationMode(.middle)
                .help(store.folder.path)
                Spacer()
                Button("Ändern …") { store.chooseFolder() }.disabled(store.downloading)
                if !store.usesDownloads {
                    Button("Downloads verwenden") { store.resetFolder() }.disabled(store.downloading)
                }
            }.font(.callout)
            HStack {
                TextField("Gerät, Modellkennung oder Version suchen (z. B. iPhone 15, iPad Air, iPhone16,1)", text: $store.query)
                    .textFieldStyle(.roundedBorder)
                Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Apple-Liste neu laden").disabled(store.loading || store.downloading)
            }
            if let item = store.active { progressCard(item) }
            if store.loading { ProgressView(store.status).padding() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(DeviceNames.Family.allCases, id: \.self) { family in
                        let group = store.visible.filter { $0.family == family }
                        if !group.isEmpty {
                            Text("\(family.title) · \(group.count)").font(.title3.bold())
                                .padding(.top, family == .iPhone ? 0 : 14)
                            ForEach(group) { item in row(item) }
                        }
                    }
                    if !store.loading && store.visible.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.largeTitle)
                            Text("Keine passende Firmware").font(.headline)
                            Text("Apple listet pro Gerät nur die aktuelle Version.").foregroundStyle(.secondary)
                        }.padding(32).frame(maxWidth: .infinity)
                    }
                }
            }
            Text(store.status + " · Ältere Versionen führt Apple nicht mehr auf und signiert sie meist nicht mehr.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { if store.items.isEmpty { await store.load() } }
        .alert("Hinweis", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func row(_ item: Firmware) -> some View {
        HStack(spacing: 16) {
            FirmwareArtwork(item: item, photo: photos.image(for: item.devices.last ?? ""))
                .frame(width: 112, height: 76).id(photos.revision)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.deviceNames.joined(separator: ", ")).font(.headline).lineLimit(2)
                Text("\(item.platform) \(item.version)  ·  Build \(item.build)").font(.subheadline).foregroundStyle(.secondary)
                Text(item.devices.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let file = store.existing(item) {
                Button("Im Finder zeigen", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            } else {
                Button("Laden", systemImage: "arrow.down") { Task { await store.start(item, studio: studio) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.downloading || studio.busy || studio.loading)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func progressCard(_ item: Firmware) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(item.deviceNames.first ?? item.fileName) · \(item.platform) \(item.version)").font(.headline)
                Spacer()
                if store.finished != nil {
                    Button("Im Finder zeigen", systemImage: "folder") {
                        if let file = store.finished { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    }
                    Button("Schließen") { store.dismiss() }
                } else {
                    Button("Abbrechen", role: .cancel) { store.cancel() }
                }
            }
            if let value = store.progress { ProgressView(value: value, total: 100) } else { ProgressView().progressViewStyle(.linear) }
            HStack {
                Text(store.phase)
                Spacer()
                if store.expected > 0 {
                    Text(String(format: "%.2f von %.2f GB", store.written / 1e9, store.expected / 1e9))
                }
                if let rate = store.mbits { Text(String(format: "%.0f Mbit/s", rate)) }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Tile like the macOS installer artwork: device outline matching the model's design plus the OS version.
struct FirmwareArtwork: View {
    let item: Firmware
    var photo: NSImage? = nil
    private var symbol: String {
        let candidates: [String]
        switch item.design {
        case .homeButton: candidates = ["iphone.gen1", "iphone.homebutton", "iphone"]
        case .notch: candidates = ["iphone.gen2", "iphone"]
        case .dynamicIsland: candidates = ["iphone.gen3", "iphone"]
        case .padHomeButton: candidates = ["ipad.gen1", "ipad.homebutton", "ipad"]
        case .padFullScreen: candidates = ["ipad.gen2", "ipad"]
        case .pod: candidates = ["ipodtouch", "iphone.homebutton", "iphone"]
        }
        return candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "iphone"
    }
    private var colors: [Color] {
        switch item.family {
        case .iPhone: [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.45, green: 0.28, blue: 0.95)]
        case .iPad: [Color(red: 0.98, green: 0.55, blue: 0.20), Color(red: 0.93, green: 0.27, blue: 0.45)]
        case .iPod: [Color(red: 0.20, green: 0.75, blue: 0.55), Color(red: 0.10, green: 0.55, blue: 0.75)]
        }
    }
    var body: some View {
        if let photo {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                Image(nsImage: photo).resizable().interpolation(.high).antialiased(true).scaledToFit().padding(5)
                Text("\(item.platform) \(item.version.split(separator: ".").first ?? "")")
                    .font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.black.opacity(0.65), in: Capsule()).padding(4)
            }
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
            .accessibilityLabel("\(item.deviceNames.first ?? "Gerät"), Foto von Apple")
        } else {
            symbolTile.frame(width: 58, height: 58).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var symbolTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 24, weight: .regular)).foregroundStyle(.white)
                Text("\(item.platform) \(item.version.split(separator: ".").first ?? "")")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }.padding(4)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
        .accessibilityLabel("\(item.deviceNames.first ?? "Gerät") Firmware-Symbol")
    }
}
