import AppKit
import SwiftUI
import StudioCore

@MainActor final class StudioModel: ObservableObject {
    @Published var installers: [Installer] = []
    @Published var models: [MacModel] = []
    @Published var disks: [ExternalDisk] = []
    @Published var localInstallers: [String] = []
    @Published var localItems: [LocalInstaller] = []
    @Published var localScanning = false
    @Published var localNotice = ""
    private var extraLocalPaths: Set<String> = []
    private let fileAccess = SavedFileAccess()
    @Published var selectedInstaller = ""
    @Published var selectedDisk = ""
    /// Target Mac filter for the installer list; remembered between launches.
    @Published var selectedMac = "" { didSet { UserDefaults.standard.set(selectedMac, forKey: "selectedTargetMac") } }
    @Published var section = "download"
    @Published var query = ""
    @Published var modelQuery = ""
    @Published var detectingMac = false
    @Published var detectedMacID = ""
    @Published var loading = false
    @Published var scanning = false
    @Published var busy = false
    @Published var flashing = false
    @Published var status = String(localized: "Bereit")
    @Published var catalogStatus = String(localized: "Apple-Katalog noch nicht geladen")
    @Published var progress: Double?
    @Published var amount: Double?
    @Published var mbits: Double?
    @Published var total: Double = 0
    @Published var activeTitle = ""
    @Published var log = ""
    @Published var error: String?
    /// Privacy pane anchor to offer with the current error, if any.
    @Published var privacyPane: String?
    static let terminalAccessHint = String(localized: "macOS hat Terminal den Schreibzugriff auf den USB-Stick verweigert (250). Bitte unter Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff „Terminal“ aktivieren, Terminal beenden und die USB-Erstellung erneut starten. Alternativ genügt bei „Dateien und Ordner“ für Terminal der Zugriff auf „Wechselmedien“.")
    /// Set while the Terminal job runs; the user can cancel it from the app.
    @Published var waitingForTerminal = false
    @Published private(set) var cancelRequestedAt: Date?
    private var activeJob: TerminalJob?
    func cancelTerminalJob() {
        guard let job = activeJob, cancelRequestedAt == nil else { return }
        job.requestCancel(); cancelRequestedAt = Date()
        status = String(localized: "Abbruch angefordert …")
    }
    /// Apple's tool needs room for the whole installer plus boot files; at least 16 GB.
    static func requiredUSBBytes(installerBytes: Int64?) -> Double {
        max(16e9, Double(installerBytes ?? 0) + 1.5e9)
    }
    @Published var completedPath = ""
    private var command: Command?
    private var packageDownload: PackageDownload?
    private var metrics = ProgressMetrics()
    private var lastProgress = Date()
    private var lastSample: ProgressSample?
    private var buffer = ""
    private var stopReason: String?

    init() {
        if let url = Bundle.module.url(forResource: "models", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            models = (try? JSONDecoder().decode([MacModel].self, from: data)) ?? []
        }
        if let saved = UserDefaults.standard.string(forKey: "selectedTargetMac"), models.contains(where: { $0.id == saved }) {
            selectedMac = saved
        }
        extraLocalPaths.formUnion(fileAccess.installers)
        refreshLocal()
        discovery = DeviceDiscoveryStore(builtInMacs: Set(models.flatMap(\.identifiers)))
        models += discovery.macModels
        if let saved = UserDefaults.standard.string(forKey: "selectedTargetMac"), models.contains(where: { $0.id == saved }) { selectedMac = saved }
    }
    /// New iPhones, iPads and Macs found at runtime (Apple's lists + AppleDB).
    private(set) var discovery: DeviceDiscoveryStore!

    /// Daily check for devices newer than this app; new Macs join "Mac suchen".
    func refreshDevices(force: Bool = false) async {
        await discovery.refresh(force: force)
        mergeDiscoveredMacs()
    }
    private func mergeDiscoveredMacs() {
        let known = Set(models.flatMap(\.identifiers))
        let added = discovery.macModels.filter { !$0.identifiers.contains(where: known.contains) }
        if !added.isEmpty { models += added }
    }
    var currentMac: MacModel? { models.first { $0.id == selectedMac } }
    /// Settings: list installers this Mac cannot run itself (for other Macs).
    @Published var showOtherMacInstallers = UserDefaults.standard.object(forKey: AppSettings.otherMacsKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(showOtherMacInstallers, forKey: AppSettings.otherMacsKey) }
    }
    var filteredInstallers: [Installer] {
        installers.filter { item in
            (showOtherMacInstallers || item.offeredForThisMac) &&
            (query.isEmpty || "\(item.title) \(item.version) \(item.build)".localizedCaseInsensitiveContains(query)) &&
            (currentMac == nil || currentMac!.supports(item))
        }
    }
    var filteredModels: [MacModel] {
        if case .found(let serial, _, let ids) = serialState, serial == SerialLookup.normalized(modelQuery) {
            return models.filter { ids.contains($0.id) }
        }
        return models.filter { $0.matches(query: modelQuery) }
    }
    enum SerialState: Equatable {
        case idle, searching
        case found(serial: String, appleName: String, ids: [String])
        case unmatched(serial: String, appleName: String)
        case randomized(serial: String)
        case unknown(serial: String)
        case failed(serial: String)
    }
    @Published var serialState: SerialState = .idle
    var serialSearchAvailable: Bool {
        MacModel.isSerialQuery(modelQuery) && models.allSatisfy { !$0.matches(query: modelQuery) }
    }
    func resetSerialStateIfStale() {
        let serial = SerialLookup.normalized(modelQuery)
        switch serialState {
        case .found(let s, _, _) where s == serial, .unmatched(let s, _) where s == serial,
             .randomized(let s) where s == serial, .unknown(let s) where s == serial, .failed(let s) where s == serial: return
        case .idle: return
        default: serialState = .idle
        }
    }
    /// Resolves the serial in the app via Apple's product lookup; never opens a browser.
    func searchSerial() async {
        let serial = SerialLookup.normalized(modelQuery)
        guard serialSearchAvailable else { serialState = .idle; return }
        switch serialState {
        case .found(let s, _, _) where s == serial, .unmatched(let s, _) where s == serial,
             .randomized(let s) where s == serial, .unknown(let s) where s == serial: return
        default: break
        }
        if SerialLookup.isRandomized(serial) { serialState = .randomized(serial: serial); return }
        guard let code = SerialLookup.configCode(for: serial), let url = SerialLookup.url(for: code) else {
            serialState = .unknown(serial: serial); return
        }
        serialState = .searching
        do {
            let (data, _) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            guard SerialLookup.normalized(modelQuery) == serial else { return }
            guard let name = SerialLookup.modelName(fromResponse: String(decoding: data, as: UTF8.self)) else {
                serialState = .unknown(serial: serial); return
            }
            let found = SerialLookup.matches(for: name, in: models)
            serialState = found.isEmpty ? .unmatched(serial: serial, appleName: name) : .found(serial: serial, appleName: name, ids: found.map(\.id))
        } catch {
            if SerialLookup.normalized(modelQuery) == serial { serialState = .failed(serial: serial) }
        }
    }

    var disk: ExternalDisk? { disks.first { $0.id == selectedDisk } }
    var canFlash: Bool { !busy && !loading && !scanning && disk != nil && !selectedInstaller.isEmpty && validInstaller(selectedInstaller) }

    func appendLog(_ text: String) {
        log += text
        if log.utf8.count > 60_000 { log = String(log.suffix(50_000)) }
    }
    func refreshLocal() {
        let roots = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        let paths = roots.flatMap { root in
            ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).map { root + "/" + $0 }
        }
        localInstallers = Array(Set(paths).union(extraLocalPaths)).filter { validInstaller($0) }.sorted()
        if !selectedInstaller.isEmpty && validInstaller(selectedInstaller) && !localInstallers.contains(selectedInstaller) {
            localInstallers.append(selectedInstaller)
        }
        if !localInstallers.contains(selectedInstaller) { selectedInstaller = localInstallers.first ?? "" }
    }
    func validInstaller(_ path: String) -> Bool {
        LocalInstaller.preparationIssue(at: path) == nil
    }
    func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            do { try fileAccess.remember(url) } catch { self.error = String(localized: "Speicherort konnte nicht dauerhaft gespeichert werden: ") + error.localizedDescription; return }
            guard FileManager.default.isExecutableFile(atPath: url.path + "/Contents/Resources/createinstallmedia") else {
                error = String(localized: "Die App enthält kein ausführbares createinstallmedia."); return
            }
            if let issue = LocalInstaller.preparationIssue(at: url.path) {
                extraLocalPaths.insert(url.path)
                error = issue
                Task { await scanLocal() }
                return
            }
            selectedInstaller = url.path; extraLocalPaths.insert(url.path); refreshLocal()
            Task { await scanLocal() }
        }
    }
    func chooseSearchFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = String(localized: "Ordner für die Installer-Suche freigeben. Die Auswahl wird für kommende Starts gespeichert.")
        panel.prompt = String(localized: "Ordner merken")
        if panel.runModal() == .OK, let url = panel.url {
            do { try fileAccess.remember(url); Task { await scanLocal() } }
            catch { self.error = String(localized: "Ordnerauswahl konnte nicht gespeichert werden: ") + error.localizedDescription }
        }
    }
    func scanLocal() async {
        guard !localScanning else { return }
        localScanning = true
        defer { localScanning = false }
        refreshLocal()
        let known = localInstallers
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["/Applications", home.appendingPathComponent("Applications").path] + fileAccess.directories
        let items = await Task.detached(priority: .utility) {
            LocalInstaller.discover(roots: roots, known: known)
        }.value
        localItems = items
        extraLocalPaths.formUnion(items.map(\.path))
        refreshLocal()
    }
    @Published var verifyingLocal = false
    /// Re-checks a local macOS installer's structure (Apple publishes no per-app checksum) (#3).
    func verifyLocal(_ item: LocalInstaller) async {
        guard !busy && !verifyingLocal else { return }
        verifyingLocal = true
        defer { verifyingLocal = false }
        localNotice = String(localized: "„\(item.name)“ wird geprüft …")
        let path = item.path
        let fresh = await Task.detached(priority: .userInitiated) { LocalInstaller.inspect(path) }.value
        guard let fresh else { localNotice = String(localized: "„\(item.name)“ ist nicht mehr auffindbar. Liste aktualisieren."); return }
        if let issue = fresh.preparationIssue {
            localNotice = "„\(item.name)“: \(issue)"
        } else {
            let size = fresh.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "unbekannt"
            localNotice = String(localized: "„\(item.name)“: OK – vollständige Installationsdaten vorhanden (\(size)). Bereit für die USB-Erstellung.")
        }
    }
    func trashLocal(_ item: LocalInstaller) async {
        guard !busy && !localScanning && localItems.contains(item) else { return }
        busy = true
        localNotice = String(localized: "Installer wird in den Papierkorb verschoben …")
        do {
            do {
                try await Task.detached(priority: .utility) { try item.moveToTrash() }.value
            } catch {
                let problem = error as NSError
                let posix = (problem.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
                let denied = (problem.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(problem.code))
                    || posix == EPERM || posix == EACCES
                guard denied else { throw error }
                try await trashWithAdministrator(item)
                guard !FileManager.default.fileExists(atPath: item.path) else { throw failure(String(localized: "Der Installer wurde nicht verschoben. Bitte erneut prüfen.")) }
            }
            extraLocalPaths.remove(item.path)
            if selectedInstaller == item.path { selectedInstaller = "" }
            if completedPath == item.path { completedPath = "" }
            localItems.removeAll { $0.path == item.path }
            refreshLocal()
            localNotice = String(localized: "„\(item.name)“ wurde in den Papierkorb verschoben. Speicher wird erst beim Leeren des Papierkorbs freigegeben.")
        } catch {
            localNotice = String(localized: "Installer konnte nicht entfernt werden.")
            self.error = error.localizedDescription
        }
        busy = false
    }
    /// Root-owned installers: first let Finder trash them (it asks for the password itself), then fall back to
    /// handing ownership to the user. macOS "App Management" can block both for apps in /Applications.
    private func trashWithAdministrator(_ item: LocalInstaller) async throws {
        localNotice = String(localized: "Finder verschiebt den Installer in den Papierkorb – bitte ggf. das Passwort eingeben …")
        let script = try await Task.detached(priority: .utility) { try item.finderTrashScript() }.value
        let finder = try await Command().run("/usr/bin/osascript", ["-e", script], timeout: .greatestFiniteMagnitude)
        if finder.status == 0 && !FileManager.default.fileExists(atPath: item.path) { return }
        if finder.output.contains("(-128)") { throw failure(String(localized: "Entfernen abgebrochen. Der Installer bleibt erhalten.")) }
        let automationDenied = finder.output.contains("(-1743)")
        localNotice = String(localized: "Administratorfreigabe zum Verschieben in den Papierkorb erforderlich …")
        let shell = try await Task.detached(priority: .utility) {
            try item.authorizedOwnershipCommand(owner: getuid())
        }.value
        let result = try await Command().run("/usr/bin/osascript",
            ["-e", "do shell script " + appleScriptQuote(shell) + " with administrator privileges"], timeout: .greatestFiniteMagnitude)
        if result.output.contains("(-128)") { throw failure(String(localized: "Entfernen abgebrochen. Der Installer bleibt erhalten.")) }
        guard result.status == 0 else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            if automationDenied {
                privacyPane = "Privacy_Automation"
                throw failure(String(localized: "macOS hat OS Studio die Steuerung des Finders verweigert. Bitte unter Systemeinstellungen → Datenschutz & Sicherheit → Automation bei „OS Studio“ den Finder erlauben und erneut löschen.\n\nAlternativ den im Finder markierten Installer selbst in den Papierkorb ziehen."))
            }
            privacyPane = result.output.contains("Operation not permitted") ? "Privacy_AppBundles" : nil
            throw failure(String(localized: "macOS schützt den Installer vor Änderungen durch andere Apps („App-Verwaltung“). Der Installer ist jetzt im Finder markiert: Einfach in den Papierkorb ziehen und mit dem Passwort bestätigen.\n\nAlternativ unter Systemeinstellungen → Datenschutz & Sicherheit → App-Verwaltung „OS Studio“ aktivieren und erneut löschen."))
        }
        // Ownership changed; revalidate the same bundle and trash it as the user.
        try await Task.detached(priority: .utility) {
            guard let current = LocalInstaller.inspect(item.path), current.path == item.path, current.bytes == item.bytes else {
                throw NSError(domain: "LocalInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "Der Installer wurde verändert. Bitte die Liste aktualisieren.")])
            }
            try current.moveToTrash()
        }.value
    }
    func loadCatalog() async {
        guard !loading && !busy else { return }
        loading = true; catalogStatus = String(localized: "Apple-Katalog wird geprüft … maximal 90 Sekunden")
        defer { loading = false }
        async let offeredResult = Self.offeredInstallers()
        async let catalogResult = Self.catalogInstallers()
        let (offered, catalog) = await (offeredResult, catalogResult)
        let merged = AppleCatalog.merge(offered: (try? offered.get()) ?? [], catalog: (try? catalog.get()) ?? [])
        guard !merged.isEmpty else {
            catalogStatus = String(localized: "Katalog konnte nicht geladen werden")
            let reasons = [offered, catalog].compactMap { result -> String? in
                if case .failure(let problem) = result { return problem.localizedDescription }; return nil
            }
            error = reasons.isEmpty ? String(localized: "Apple bietet keine Installer an.") : reasons.joined(separator: "\n\n")
            return
        }
        installers = merged
        let extra = merged.filter { !$0.offeredForThisMac }.count
        catalogStatus = "\(merged.count) Versionen abrufbar · Apple-Katalog" + (extra > 0 ? String(localized: " · \(extra) davon nicht für diesen Mac, Download als Apple-Paket für andere Macs") : "")
        if case .failure = catalog, extra == 0 { catalogStatus += String(localized: " · vollständiger Katalog nicht erreichbar") }
    }
    private nonisolated static func offeredInstallers() async -> Result<[Installer], Error> {
        do {
            let result = try await Command().run("/usr/sbin/softwareupdate", ["--list-full-installers"], timeout: 90)
            guard !result.timedOut else { throw failure(String(localized: "Apple antwortet nicht. Verbindung prüfen und erneut laden.")) }
            guard result.status == 0 else { throw failure(result.output) }
            return .success(Installer.parse(result.output))
        } catch { return .failure(error) }
    }
    /// Every full installer in Apple's public catalog, including versions this Mac cannot install itself.
    private nonisolated static func catalogInstallers() async -> Result<[Installer], Error> {
        do {
            var request = URLRequest(url: AppleCatalog.url, timeoutInterval: 60)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure(String(localized: "Apple-Katalog nicht erreichbar.")) }
            let products = AppleCatalog.products(fromCatalog: try Gzip.decompress(data))
            let items = await withTaskGroup(of: Installer?.self) { group in
                for product in products {
                    group.addTask {
                        guard let (text, _) = try? await URLSession.shared.data(for: URLRequest(url: product.distribution, timeoutInterval: 30)),
                              let info = AppleCatalog.describe(distribution: String(decoding: text, as: UTF8.self)) else { return nil }
                        return Installer(title: info.title, version: info.version, build: info.build, bytes: product.bytes,
                                         packageURL: product.package, packageParts: product.parts, offeredForThisMac: false)
                    }
                }
                var collected: [Installer] = []
                for await item in group { if let item { collected.append(item) } }
                return collected
            }
            // Apple occasionally lists the same build twice; keep one.
            var seen = Set<String>()
            return .success((items + AppleCatalog.diskImageInstallers).filter { seen.insert($0.version + $0.build).inserted })
        } catch { return .failure(error) }
    }
    private nonisolated static func failure(_ message: String) -> NSError { NSError(domain: "MacOSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func download(_ item: Installer) async {
        guard !busy && !loading else { return }
        guard Installer.validVersion(item.version) else { error = String(localized: "Bitte eine Version wie 15.7.2 eingeben."); return }
        busy = true
        status = String(localized: "Vorhandene Installer werden geprüft …")
        completedPath = ""; error = nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["/Applications", home.appendingPathComponent("Applications").path] + fileAccess.directories
        let known = Array(extraLocalPaths.union(localInstallers))
        let found = await Task.detached(priority: .utility) {
            LocalInstaller.discover(roots: roots, known: known)
        }.value
        localItems = found
        extraLocalPaths.formUnion(found.map(\.path))
        refreshLocal()
        busy = false
        if let existing = found.first(where: { $0.matches(item) }) {
            completedPath = existing.path; selectedInstaller = existing.path
            activeTitle = item.title + " " + item.version
            progress = 100; total = Double(existing.bytes ?? 0); amount = total; mbits = nil
            status = String(localized: "Passender Installer bereits vorhanden – kein Download nötig")
            log = "Vorhandener Installer: \(existing.path)\n"
            error = String(localized: "Dieser Installer ist bereits vorhanden:\n\(existing.path)\n\nVersion und Installationsdaten wurden erkannt. Er wurde für die USB-Erstellung ausgewählt; ein erneuter Download ist nicht nötig.")
            return
        }
        // A manual request is titled only "macOS" and would match every installer; skip the series check.
        let manual = item.build == "Manuell"
        if !manual, let existing = found.first(where: { $0.name.localizedCaseInsensitiveContains(item.title) }) {
            status = String(localized: "Vorhandenen Installer prüfen")
            if let issue = existing.preparationIssue {
                error = String(localized: "\(existing.path)\n\n\(issue)\nBitte unter „Installer lokal“ in den Papierkorb verschieben und danach erneut laden.")
            } else {
                error = String(localized: "Ein Installer dieser macOS-Reihe ist bereits vorhanden:\n\(existing.path)\n\nDie gewünschte Version \(item.version) (\(item.build)) konnte nicht bestätigt werden. Bitte unter „Installer lokal“ prüfen. Für einen neuen Download den vorhandenen Installer zuerst an einen anderen Ort verschieben oder in den Papierkorb legen.")
            }
            return
        }
        // Same rule as everywhere else: unknown free space does not block. Apple packages are first
        // stored in ~/Library/Caches, the finished installer lands in /Applications – check both volumes.
        let need = Int64(max(item.bytes * 2 + 5e9, 20e9))
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path
        guard Disk.hasSpace(forPath: "/Applications", need: need, margin: 0), Disk.hasSpace(forPath: caches, need: need, margin: 0) else {
            error = String(localized: "Nicht genügend freier Speicher für Download und Entpacken."); return
        }
        if !item.offeredForThisMac, item.packageURL != nil { await downloadPackage(item); return }
        busy = true; flashing = false; completedPath = ""; log = ""; activeTitle = item.title + " " + item.version
        total = item.bytes; amount = nil; mbits = nil; progress = nil
        metrics.reset(); lastSample = nil; lastProgress = Date(); buffer = ""; stopReason = nil
        status = String(localized: "Apple prüft die Verfügbarkeit …")
        let before = Dictionary(uniqueKeysWithValues: localInstallers.map { ($0, modification($0)) })
        let cmd = Command(); command = cmd
        let monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let elapsed = Date().timeIntervalSince(self.lastProgress)
                if elapsed > 15 { self.mbits = nil }
                let limit: Double = self.lastSample == nil ? 180 : 900
                if elapsed > limit {
                    self.stopReason = self.lastSample == nil ? String(localized: "Apple meldet nach 3 Minuten keinen Downloadfortschritt. Katalog neu laden und erneut versuchen.") : String(localized: "Seit 15 Minuten kein Fortschritt. Verbindung und Speicher prüfen.")
                    cmd.cancel(); return
                }
            }
        }
        defer { monitor.cancel(); command = nil; busy = false; mbits = nil; DockProgress.clear() }
        do {
            let result = try await cmd.run("/usr/sbin/softwareupdate", ["--fetch-full-installer", "--full-installer-version", item.version], timeout: 24 * 3600) { [weak self] text in
                Task { @MainActor in self?.consume(text) }
            }
            // Process the complete output once more to include a final unterminated line.
            if let sample = ProgressSample.parse(result.output) { update(sample) }
            if let reason = stopReason { throw failure(reason) }
            if result.cancelled { status = String(localized: "Download abgebrochen"); return }
            guard result.status == 0 && !result.timedOut else { throw failure(String(result.output.suffix(1800))) }
            refreshLocal()
            let changed = localInstallers.filter { before[$0] == nil || before[$0] != modification($0) }
            let named = localInstallers.filter { URL(fileURLWithPath: $0).lastPathComponent.localizedCaseInsensitiveContains(item.title) }
            let candidate = manual ? (changed.count == 1 ? changed.first : nil)
                : (named.count == 1 ? named.first : (changed.count == 1 ? changed.first : nil))
            guard let path = candidate else {
                throw failure(String(localized: "Apple hat den Vorgang beendet, aber kein passender Installer mit Installationsdaten wurde gefunden. Unter „Installer lokal“ kannst du unvollständige Downloads prüfen und entfernen."))
            }
            completedPath = path; selectedInstaller = path; progress = 100; amount = total > 0 ? total : nil
            status = String(localized: "Installer geladen und geprüft")
        } catch { status = String(localized: "Download fehlgeschlagen"); self.error = error.localizedDescription }
    }
    /// Catalog-only installers: download Apple's InstallAssistant.pkg, verify it and let macOS' installer
    /// create "Install macOS ….app" in /Applications. Works on Macs that cannot run this macOS themselves.
    private func downloadPackage(_ item: Installer) async {
        guard let url = item.packageURL else { return }
        if item.assembledFromParts { await downloadParts(item); return }
        packageCancelled.reset()
        busy = true; flashing = false; completedPath = ""; log = ""; activeTitle = item.title + " " + item.version
        total = item.bytes; amount = nil; mbits = nil; progress = 0
        status = String(localized: "Apple-Paket wird geladen …")
        defer { packageDownload = nil; busy = false; mbits = nil }
        let package = Self.packageFile(item)
        appendLog("Quelle: \(url.absoluteString)\n")
        do {
            try FileManager.default.createDirectory(at: package.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await fetch(url, expected: Int64(item.bytes), to: package, offset: 0, total: Int64(item.bytes), label: String(localized: "Apple-Paket wird geladen"))
            mbits = nil; progress = 95
            let size = ((try? FileManager.default.attributesOfItem(atPath: package.path)[.size]) as? NSNumber)?.doubleValue ?? 0
            guard item.bytes <= 0 || size == item.bytes else {
                try? FileManager.default.removeItem(at: package)
                throw failure(String(localized: "Das geladene Paket ist unvollständig (\(Int64(size)) statt \(Int64(item.bytes)) Bytes). Bitte erneut laden."))
            }
            if let part = item.packageParts.first, part.integrity != nil {
                try await verifyPart(part, file: package, from: 95, to: 96.5)
            }
            status = String(localized: "Apple-Signatur wird geprüft …")
            let signature = try await Command().run("/usr/sbin/pkgutil", ["--check-signature", package.path], timeout: 600)
            appendLog(signature.output)
            guard signature.status == 0, signature.output.contains("signed Apple Software") else {
                try? FileManager.default.removeItem(at: package)
                throw failure(String(localized: "Das Paket ist nicht von Apple signiert und wird nicht installiert.\n\n") + signature.output)
            }
            status = String(localized: "Installer-App wird erstellt – bitte Administratorpasswort eingeben …"); progress = 97
            let before = Dictionary(uniqueKeysWithValues: localInstallers.map { ($0, modification($0)) })
            let shell = "/usr/sbin/installer -pkg " + shellQuote(package.path) + " -target /"
            let result = try await Command().run("/usr/bin/osascript",
                ["-e", "do shell script " + appleScriptQuote(shell) + " with administrator privileges"], timeout: 3 * 3600)
            appendLog(result.output)
            if result.output.contains("(-128)") { status = String(localized: "Abgebrochen – das geladene Paket bleibt für den nächsten Versuch erhalten"); return }
            guard result.status == 0 else { throw failure(String(localized: "Apples Installer konnte die Installer-App nicht erstellen.\n\n") + String(result.output.suffix(1800))) }
            try? FileManager.default.removeItem(at: package)
            refreshLocal()
            let changed = localInstallers.filter { before[$0] == nil || before[$0] != modification($0) }
            let found = LocalInstaller.discover(roots: ["/Applications"], known: changed)
            guard let installed = found.first(where: { $0.matches(item) }) ?? (changed.count == 1 ? LocalInstaller.inspect(changed[0]) : nil) else {
                throw failure(String(localized: "Das Paket wurde installiert, aber keine passende Installer-App wurde in /Applications gefunden."))
            }
            localItems = found
            completedPath = installed.path; selectedInstaller = installed.path; progress = 100; amount = total
            status = String(localized: "Installer geladen und geprüft")
        } catch { reportPackageFailure(error, item) }
    }

    /// macOS 10.13–10.15 from Apple's catalog: downloads the installer parts, checks each against Apple's
    /// integrity data, and assembles "Install macOS ….app" from the signed InstallAssistantAuto.pkg
    /// without running the macOS installer (works on any Mac, no administrator password).
    private func downloadParts(_ item: Installer) async {
        busy = true; flashing = false; completedPath = ""; log = ""; activeTitle = item.title + " " + item.version
        total = item.bytes; amount = 0; mbits = nil; progress = 0
        packageCancelled.reset()
        let fileManager = FileManager.default
        let folder = Self.partsFolder(item)
        defer { packageDownload = nil; busy = false; mbits = nil }
        do {
            // Parts already downloaded completely stay; interrupted ones continue from their resume data.
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let parts = item.packageParts
            let totalBytes = parts.reduce(Int64(0)) { $0 + $1.bytes }
            var files: [String: URL] = [:]
            var offset: Int64 = 0
            for (index, part) in parts.enumerated() {
                let label = String(localized: "Apple-Pakete werden geladen (\(index + 1) von \(parts.count))")
                status = label + " …"
                appendLog("Quelle: \(part.url.absoluteString)\n")
                let target = folder.appendingPathComponent(part.name)
                try await fetch(part.url, expected: part.bytes, to: target, offset: offset, total: totalBytes, label: label)
                if packageCancelled.value { throw CancellationError() }
                let size = ((try? fileManager.attributesOfItem(atPath: target.path)[.size]) as? NSNumber)?.int64Value ?? -1
                guard part.bytes <= 0 || size == part.bytes else {
                    try? fileManager.removeItem(at: target)
                    throw failure(String(localized: "\(part.name) ist unvollständig (\(size) statt \(part.bytes) Bytes). Bitte erneut laden."))
                }
                files[part.name] = target
                offset += part.bytes
            }
            mbits = nil; progress = 95
            // Apple's chunked SHA-256 data per file; BaseSystem/AppleDiagnostics also come with their own chunk list.
            for part in parts where part.name.hasSuffix(".pkg") || part.name.hasSuffix(".dmg") {
                guard let file = files[part.name] else { continue }
                if part.integrity != nil {
                    try await verifyPart(part, file: file, from: 95, to: 98)
                } else if let list = files[part.name.replacingOccurrences(of: ".dmg", with: ".chunklist")], part.name.hasSuffix(".dmg") {
                    try await verifyPart(part, file: file, from: 95, to: 98, localList: list)
                } else if item.fromDiskImage {
                    try await verifyDiskImage(file)
                } else {
                    appendLog(String(localized: "\(part.name): Apple veröffentlicht keine Prüfdaten – nur Größe geprüft.\n"))
                }
            }
            if item.fromDiskImage, let image = files[parts[0].name] {
                try await assembleFromDiskImage(image, folder: folder, item: item)
                return
            }
            status = String(localized: "Apple-Signatur wird geprüft …")
            guard let stubPackage = files[AppleCatalog.legacyParts[0]] else { throw failure(String(localized: "InstallAssistantAuto.pkg fehlt.")) }
            let signature = try await Command().run("/usr/sbin/pkgutil", ["--check-signature", stubPackage.path], timeout: 600)
            appendLog(signature.output)
            guard signature.status == 0, signature.output.contains("signed Apple Software") else {
                try? fileManager.removeItem(at: stubPackage)
                throw failure(String(localized: "Das Paket ist nicht von Apple signiert und wird nicht verwendet.\n\n") + signature.output)
            }
            status = String(localized: "Installer-App wird zusammengesetzt …"); progress = 98.5
            let expanded = folder.appendingPathComponent("expanded")
            try? fileManager.removeItem(at: expanded)
            let expand = try await Command().run("/usr/sbin/pkgutil", ["--expand-full", stubPackage.path, expanded.path], timeout: 600)
            guard expand.status == 0, let app = LegacyInstaller.stubApp(inExpanded: expanded) else {
                throw failure(String(localized: "Das Apple-Paket konnte nicht entpackt werden.\n\n") + String(expand.output.suffix(1200)))
            }
            try LegacyInstaller.assemble(app: app, files: files)
            try finishAssembledApp(app, folder: folder, item: item)
        } catch { reportPackageFailure(error, item) }
    }

    // MARK: Resumable downloads of Apple packages

    private static var packagesFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.appletools.macosstudio/Packages", isDirectory: true)
    }
    private static func packageFile(_ item: Installer) -> URL { packagesFolder.appendingPathComponent("InstallAssistant-\(item.build).pkg") }
    private static func partsFolder(_ item: Installer) -> URL { packagesFolder.appendingPathComponent("\(item.build)-parts", isDirectory: true) }

    /// Deletes a work folder, but never descends into a disk image still mounted at <folder>/mount.
    private static func removeWorkFolder(_ folder: URL) {
        let fileManager = FileManager.default
        let mount = folder.appendingPathComponent("mount")
        if ((try? fileManager.contentsOfDirectory(atPath: mount.path)) ?? []).isEmpty {
            try? fileManager.removeItem(at: folder); return
        }
        for child in (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where child.lastPathComponent != "mount" {
            try? fileManager.removeItem(at: child)
        }
    }

    /// True when an earlier download of this installer left data to continue from.
    func canResume(_ item: Installer) -> Bool {
        guard item.packageURL != nil, !item.offeredForThisMac else { return false }
        let fileManager = FileManager.default
        if item.assembledFromParts {
            let entries = (try? fileManager.contentsOfDirectory(atPath: Self.partsFolder(item).path)) ?? []
            return entries.contains { !$0.hasPrefix(".") && $0 != "expanded" && $0 != "mount" }
        }
        let file = Self.packageFile(item)
        return fileManager.fileExists(atPath: file.path) || fileManager.fileExists(atPath: file.path + ".resume")
    }
    /// Deletes the kept partial download of this installer.
    func discardPartial(_ item: Installer) {
        guard !busy else { return }
        let file = Self.packageFile(item)
        for url in [file, URL(fileURLWithPath: file.path + ".resume")] { try? FileManager.default.removeItem(at: url) }
        Self.removeWorkFolder(Self.partsFolder(item))
        objectWillChange.send()
    }

    /// Downloads one file. A complete file is kept and skipped; after an interruption the download continues
    /// from the resume data saved next to it (`<file>.resume`), even after the app was restarted.
    private func fetch(_ url: URL, expected: Int64, to target: URL, offset: Int64, total: Int64, label: String) async throws {
        let fileManager = FileManager.default
        let resume = URL(fileURLWithPath: target.path + ".resume")
        if expected > 0, ((try? fileManager.attributesOfItem(atPath: target.path)[.size]) as? NSNumber)?.int64Value == expected {
            try? fileManager.removeItem(at: resume)
            appendLog(String(localized: "\(target.lastPathComponent): bereits vollständig geladen\n"))
            packageProgress(written: offset + expected, expected: total, label: label, force: true)
            return
        }
        let resumeData = try? Data(contentsOf: resume)
        if resumeData != nil { appendLog(String(localized: "\(target.lastPathComponent): Download wird fortgesetzt\n")); status = label + String(localized: " – wird fortgesetzt …") }
        let downloader = PackageDownload(); packageDownload = downloader
        packageSample = (ProcessInfo.processInfo.systemUptime, -1)
        do {
            _ = try await downloader.run(url, to: target, resumeFrom: resumeData) { [weak self] written, _ in
                Task { @MainActor in self?.packageProgress(written: offset + written, expected: total, label: label) }
            }
            try? fileManager.removeItem(at: resume)
        } catch {
            // PackageDownload only reports a cancellation once its resume data has been handed over.
            if let data = downloader.resumeData {
                try? data.write(to: resume, options: .atomic)
            } else if resumeData != nil {
                // Stale resume data (e.g. the partial temp file was purged) fails every time: start this file fresh.
                try? fileManager.removeItem(at: resume)
                let cancelled = (error as? URLError)?.code == .cancelled || packageCancelled.value
                if !cancelled {
                    appendLog(String(localized: "\(target.lastPathComponent): Fortsetzen nicht möglich – Download beginnt neu\n"))
                    try await fetch(url, expected: expected, to: target, offset: offset, total: total, label: label)
                    return
                }
            }
            throw error
        }
    }

    private func reportPackageFailure(_ error: Error, _ item: Installer) {
        let resumable = canResume(item)
        if (error as? URLError)?.code == .cancelled || error is CancellationError {
            status = resumable ? String(localized: "Download angehalten – „Fortsetzen“ lädt ab hier weiter") : String(localized: "Download abgebrochen")
            return
        }
        status = String(localized: "Download fehlgeschlagen")
        self.error = error.localizedDescription + (resumable ? String(localized: "\n\nBereits geladene Daten bleiben erhalten. „Fortsetzen“ lädt ab der Abbruchstelle weiter.") : "")
    }

    /// Checks the disk image's own checksums (UDIF) – Apple publishes no separate integrity data for it.
    private func verifyDiskImage(_ image: URL) async throws {
        status = String(localized: "Prüfsumme des Apple-Abbilds wird geprüft …"); progress = 96
        let result = try await Command().run("/usr/bin/hdiutil", ["verify", "-quiet", image.path], timeout: 1800)
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: image)
            throw failure(String(localized: "Das Apple-Abbild \(image.lastPathComponent) ist beschädigt und wurde verworfen. Bitte erneut laden.\n\n") + String(result.output.suffix(800)))
        }
        appendLog(String(localized: "\(image.lastPathComponent): Prüfsumme des Abbilds bestätigt.\n"))
    }

    /// OS X 10.10 – macOS 10.12: mount Apple's disk image, check the package signature, expand the package
    /// and put InstallESD.dmg into the installer app. The macOS installer itself is not run (it refuses newer systems).
    private func assembleFromDiskImage(_ image: URL, folder: URL, item: Installer) async throws {
        let fileManager = FileManager.default
        let mount = folder.appendingPathComponent("mount", isDirectory: true)
        let expanded = folder.appendingPathComponent("expanded", isDirectory: true)
        _ = try? await Command().run("/usr/bin/hdiutil", ["detach", "-force", mount.path], timeout: 60)
        try? fileManager.removeItem(at: expanded)
        try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
        status = String(localized: "Apple-Abbild wird geöffnet …"); progress = 97
        let attach = try await Command().run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", mount.path, image.path], timeout: 600)
        guard attach.status == 0 else { throw failure(String(localized: "Das Apple-Abbild ließ sich nicht öffnen.\n\n") + String(attach.output.suffix(800))) }
        func detach() async { _ = try? await Command().run("/usr/bin/hdiutil", ["detach", "-force", mount.path], timeout: 120) }
        let app: URL
        do {
            let packages = ((try? fileManager.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "pkg" }
            guard packages.count == 1 else { throw failure(String(localized: "Im Apple-Abbild wurde kein eindeutiges Installationspaket gefunden.")) }
            status = String(localized: "Apple-Signatur wird geprüft …")
            let signature = try await Command().run("/usr/sbin/pkgutil", ["--check-signature", packages[0].path], timeout: 600)
            appendLog(signature.output)
            guard signature.status == 0, signature.output.contains("signed Apple Software") else {
                throw failure(String(localized: "Das Paket ist nicht von Apple signiert und wird nicht verwendet.\n\n") + signature.output)
            }
            status = String(localized: "Installer-App wird zusammengesetzt …"); progress = 98
            let expand = try await Command().run("/usr/sbin/pkgutil", ["--expand-full", packages[0].path, expanded.path], timeout: 3600)
            guard expand.status == 0, let contents = LegacyInstaller.diskImageContents(inExpanded: expanded) else {
                throw failure(String(localized: "Das Apple-Paket konnte nicht entpackt werden.\n\n") + String(expand.output.suffix(1200)))
            }
            try LegacyInstaller.assemble(app: contents.app, installESD: contents.esd)
            app = contents.app
        } catch { await detach(); throw error }
        await detach()                                  // before the work folder (with the mount point) is removed
        try finishAssembledApp(app, folder: folder, item: item)
    }

    /// Moves an assembled installer app to /Applications (or ~/Applications) and selects it.
    private func finishAssembledApp(_ app: URL, folder: URL, item: Installer) throws {
        let destination = try installDestination(for: app.lastPathComponent)
        try FileManager.default.moveItem(at: app, to: destination)
        appendLog("Installer-App: \(destination.path)\n")
        guard let installed = LocalInstaller.inspect(destination.path), installed.preparationIssue == nil else {
            throw failure(String(localized: "Die Installer-App wurde erstellt, ist aber unvollständig:\n\(destination.path)"))
        }
        extraLocalPaths.insert(installed.path)
        refreshLocal()
        localItems = (localItems.filter { $0.path != installed.path } + [installed])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        Self.removeWorkFolder(folder)
        completedPath = installed.path; selectedInstaller = installed.path; progress = 100; amount = total
        status = String(localized: "Installer geladen und geprüft")
    }

    /// /Applications when writable, otherwise ~/Applications. Never replaces an existing app.
    private func installDestination(for name: String) throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        for folder in [URL(fileURLWithPath: "/Applications", isDirectory: true), home] {
            let target = folder.appendingPathComponent(name)
            if fileManager.fileExists(atPath: target.path) {
                throw failure(String(localized: "„\(name)“ ist bereits vorhanden:\n\(target.path)\n\nBitte unter „Installer lokal“ prüfen oder vorher in den Papierkorb legen."))
            }
            if folder == home { try? fileManager.createDirectory(at: home, withIntermediateDirectories: true) }
            if fileManager.isWritableFile(atPath: folder.path) { return target }
        }
        throw failure(String(localized: "Weder /Applications noch ~/Applications sind beschreibbar."))
    }

    /// Checks a downloaded file against Apple's chunked SHA-256 list (remote integrity data or a local .chunklist).
    private func verifyPart(_ part: CatalogPart, file: URL, from start: Double, to end: Double, localList: URL? = nil) async throws {
        status = String(localized: "Apple-Prüfsumme wird geprüft: \(part.name) …")
        let data: Data
        if let localList {
            data = try Data(contentsOf: localList)
        } else if let source = part.integrity {
            let (loaded, response) = try await URLSession.shared.data(for: URLRequest(url: source, timeoutInterval: 60))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw failure(String(localized: "Apples Prüfdaten für \(part.name) sind nicht erreichbar. Bitte später erneut versuchen."))
            }
            data = loaded
        } else { return }
        guard let list = Chunklist.parse(data) else { throw failure(String(localized: "Apples Prüfdaten für \(part.name) sind unlesbar.")) }
        let cancelled = packageCancelled
        let outcome = try await Task.detached(priority: .userInitiated) { [weak self] in
            try list.verify(file, isCancelled: { cancelled.value }) { fraction in
                Task { @MainActor in
                    guard let self, self.busy else { return }
                    self.progress = start + (end - start) * fraction
                }
            }
        }.value
        switch outcome {
        case .ok: appendLog(String(localized: "\(part.name): Prüfsumme bestätigt (\(list.chunks.count) Blöcke, SHA-256).\n"))
        case .wrongSize(let expected, let actual):
            try? FileManager.default.removeItem(at: file)
            throw failure(String(localized: "\(part.name) hat die falsche Größe (\(actual) statt \(expected) Bytes). Bitte erneut laden."))
        case .mismatch(let chunk):
            try? FileManager.default.removeItem(at: file)
            throw failure(String(localized: "\(part.name) stimmt nicht mit Apples Prüfsumme überein (Block \(chunk + 1)). Die Datei wurde verworfen; bitte erneut laden."))
        }
    }
    private let packageCancelled = CancelFlag()
    private var packageSample: (time: TimeInterval, bytes: Int64) = (0, 0)
    private func packageProgress(written: Int64, expected: Int64, label: String = String(localized: "Apple-Paket wird geladen"), force: Bool = false) {
        guard busy else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if packageSample.bytes < 0 {
            packageSample = (now, written)          // resumed downloads start counting at the resume offset
        } else {
            guard force || now - packageSample.time >= 1 else { return }
            if !force { mbits = Double(written - packageSample.bytes) * 8 / (now - packageSample.time) / 1_000_000 }
            packageSample = (now, written)
        }
        let size = expected > 0 ? Double(expected) : total
        if size > 0 { total = size; progress = min(95, Double(written) / size * 95) }
        amount = Double(written); status = label
    }
    private func modification(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date ?? .distantPast
    }
    private func consume(_ text: String) {
        appendLog(text)
        buffer += text
        if let sample = ProgressSample.parse(buffer) { update(sample) }
        if buffer.utf8.count > 2048 { buffer = String(buffer.suffix(512)) }
    }
    private func update(_ sample: ProgressSample) {
        guard sample != lastSample else { return }
        if Date().timeIntervalSince(lastProgress) > 15 { metrics.reset() }
        lastSample = sample; lastProgress = Date()
        progress = min(99.9, sample.percent)
        let values = metrics.update(sample, total: total, time: ProcessInfo.processInfo.systemUptime)
        amount = values.bytes; mbits = values.mbits
        status = sample.phase == "downloading" ? String(localized: "Installer wird geladen") : String(localized: "Installer laden und vorbereiten")
        DockProgress.show(progress.map { $0 / 100 })
    }
    /// Only a macOS download started here can be cancelled from the activity panel (not IPSW downloads,
    /// iPhone restores or trashing, which also set `busy`).
    var canCancelDownload: Bool { !flashing && (command != nil || packageDownload != nil) }
    func cancel() {
        guard !flashing else { return }
        status = String(localized: "Download wird abgebrochen …"); packageCancelled.set(); command?.cancel(); packageDownload?.cancel()
    }
    func detectMac() async {
        guard !detectingMac else { return }
        detectingMac = true
        defer { detectingMac = false }
        do {
            let result = try await Command().run("/usr/sbin/sysctl", ["-n", "hw.model"], timeout: 5)
            let id = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            var match = models.first(where: { $0.identifiers.contains(id) })
            if match == nil, await discovery.resolveMac(id) != nil { mergeDiscoveredMacs(); match = models.first(where: { $0.identifiers.contains(id) }) }
            if let model = match {
                modelQuery = model.name; selectedMac = model.id; detectedMacID = model.id
            } else { modelQuery = id; error = String(localized: "\(id) ist in der übernommenen Modelldatenbank nicht enthalten.") }
        } catch { self.error = error.localizedDescription }
    }
    func scanDisks() async {
        guard !scanning && !busy else { return }
        scanning = true
        defer { scanning = false }
        refreshLocal()
        do {
            let result = try await Command().run("/usr/sbin/diskutil", ["list", "-plist", "external"], timeout: 10)
            guard result.status == 0 && !result.timedOut else { throw failure(String(localized: "Laufwerkssuche fehlgeschlagen oder Zeitlimit erreicht.")) }
            let plist = try PropertyListSerialization.propertyList(from: Data(result.output.utf8), format: nil) as? [String: Any]
            var identifiers: [String] = []
            func walk(_ obj: Any) {
                if let d = obj as? [String: Any] {
                    if let id = d["DeviceIdentifier"] as? String { identifiers.append(id) }
                    for value in d.values { if value is [Any] || value is [String: Any] { walk(value) } }
                } else if let a = obj as? [Any] { a.forEach(walk) }
            }
            if let roots = plist?["AllDisksAndPartitions"] { walk(roots) }
            var found: [ExternalDisk] = []
            for id in Set(identifiers).sorted() {
                if let disk = try? await diskInfo(id), !found.contains(where: { $0.uuid == disk.uuid }) { found.append(disk) }
            }
            disks = found
            if !disks.contains(where: { $0.id == selectedDisk }) { selectedDisk = disks.first?.id ?? "" }
        } catch { disks = []; selectedDisk = ""; self.error = error.localizedDescription }
    }
    private func diskInfo(_ identifier: String) async throws -> ExternalDisk {
        let result = try await Command().run("/usr/sbin/diskutil", ["info", "-plist", identifier], timeout: 5)
        guard result.status == 0 && !result.timedOut,
              let plist = try PropertyListSerialization.propertyList(from: Data(result.output.utf8), format: nil) as? [String: Any],
              let disk = ExternalDisk.validated(plist) else { throw failure(String(localized: "Kein geeignetes externes USB-Volume.")) }
        return disk
    }
    private func diskPlist(_ identifier: String) async throws -> [String: Any] {
        let result = try await Command().run("/usr/sbin/diskutil", ["info", "-plist", identifier], timeout: 5)
        guard result.status == 0, !result.timedOut,
              let info = try PropertyListSerialization.propertyList(from: Data(result.output.utf8), format: nil) as? [String: Any] else { throw failure(String(localized: "Laufwerksinformationen konnten nicht gelesen werden.")) }
        return info
    }
    func flash() async {
        guard canFlash, let target = disk, validInstaller(selectedInstaller) else { return }
        busy = true; flashing = true; progress = nil; amount = nil; mbits = nil; total = 0
        privacyPane = nil
        completedPath = ""
        activeTitle = String(localized: "USB-Stick erstellen"); log = ""; status = String(localized: "Ziel-Laufwerk erneut prüfen …")
        defer { busy = false; flashing = false }
        do {
            let checked = try await diskInfo(target.identifier)
            guard checked == target else { throw failure(String(localized: "Das Ziel-Laufwerk hat sich geändert. Bitte erneut auswählen.")) }
            let tool = selectedInstaller + "/Contents/Resources/createinstallmedia"
            if let issue = LocalInstaller.preparationIssue(at: selectedInstaller) { throw failure(issue) }
            if Self.hostIsARM, !MachO.architectures(of: URL(fileURLWithPath: tool)).contains("arm64") {
                status = String(localized: "Installer-Werkzeug wird geprüft …")
                let toolURL = URL(fileURLWithPath: tool)
                // Without Rosetta it cannot start at all; with Rosetta macOS kills these Apple-signed Intel tools.
                let rosetta = FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
                if await Task.detached(priority: .userInitiated, operation: { !rosetta || MachO.killedAtLaunch(toolURL) }).value {
                    throw failure(MachO.blockedOnAppleSilicon)
                }
            }
            // The stick must hold the whole installer; check before anything is erased.
            status = String(localized: "Speicherplatz auf dem USB-Stick prüfen …")
            let installerPath = selectedInstaller
            let installerBytes = await Task.detached(priority: .userInitiated) { LocalInstaller.inspect(installerPath)?.bytes }.value
            let required = Self.requiredUSBBytes(installerBytes: installerBytes)
            guard target.bytes >= required else {
                throw failure(String(localized: "Der USB-Stick ist zu klein: \(String(format: "%.1f", target.bytes / 1e9)) GB vorhanden, für diesen Installer werden mindestens \(Int((required / 1e9).rounded(.up))) GB benötigt. Der USB-Stick wurde nicht verändert."))
            }
            var preparation: USBPreparation?
            let info = try await diskPlist(target.identifier)
            if info["FilesystemType"] as? String == "apfs" {
                let result = try await Command().run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], timeout: 10)
                guard result.status == 0,
                      let list = try PropertyListSerialization.propertyList(from: Data(result.output.utf8), format: nil) as? [String: Any],
                      let containers = list["Containers"] as? [[String: Any]],
                      let container = containers.first(where: { ($0["ContainerReference"] as? String) == (info["APFSContainerReference"] as? String) }),
                      let stores = container["PhysicalStores"] as? [[String: Any]], stores.count == 1,
                      let store = stores[0]["DeviceIdentifier"] as? String else { throw failure(String(localized: "APFS-Ziel konnte nicht sicher zugeordnet werden.")) }
                let physical = try await diskPlist(store)
                guard let plan = USBPreparation(target: target, container: container, storeInfo: physical) else {
                    throw failure(String(localized: "Dieser APFS-Container enthält weitere Volumes oder lässt sich keinem einzelnen externen USB-Speicher zuordnen. Automatische Formatierung wurde gestoppt, um andere Daten zu schützen."))
                }
                preparation = plan
            }
            // Direct, escaped command; no writable temporary root shell script.
            // Recheck UUID and Internal under elevation immediately before invoking Apple's tool.
            let lookup = "/usr/sbin/diskutil info -plist " + shellQuote(target.identifier)
            let checkUUID = "$(" + lookup + " | /usr/bin/plutil -extract VolumeUUID raw -o - -)"
            let checkInternal = "$(" + lookup + " | /usr/bin/plutil -extract Internal raw -o - -)"
            let checkMount = "$(" + lookup + " | /usr/bin/plutil -extract MountPoint raw -o - -)"
            let safety = "test \"" + checkUUID + "\" = " + shellQuote(target.uuid) + " && test \"" + checkInternal + "\" = false && test \"" + checkMount + "\" = " + shellQuote(target.mount)
            let preparedName = "macOSStudio-" + UUID().uuidString.prefix(8)
            let preparedMount = "/Volumes/" + preparedName
            let volume = preparation == nil ? target.mount : preparedMount
            // Run via Terminal: with AppleScript admin privileges macOS attributes the write to the
            // system authtrampoline, which cannot be granted access, and createinstallmedia fails (250).
            let job = TerminalJob(directory: FileManager.default.temporaryDirectory.appendingPathComponent("macOSStudio-USB-" + UUID().uuidString))
            // Keep the job while Terminal may still be running (user stopped waiting); the OS cleans temp files.
            defer { if job.exitStatus() != nil { job.remove() } }
            let shell = job.usbRootCommand(safety: safety, mount: target.mount,
                                           setup: preparation?.shellCommand(name: preparedName, mount: preparedMount),
                                           tool: tool, volume: volume,
                                           application: LegacyInstaller.needsApplicationPath(tool: URL(fileURLWithPath: tool)) ? selectedInstaller : nil)
            try job.write(rootCommand: shell, headline: String(localized: "OS Studio – bootfähigen USB-Stick erstellen\nInstaller: \(selectedInstaller)\nZiel: \(target.name) (\(target.identifier)) – wird gelöscht"))
            let header = String(localized: "Installer: \(selectedInstaller)\nZiel: \(target.name) · \(target.identifier) · \(target.mount)\nDer Vorgang läuft im Terminal-Fenster; Schritte und Fortschritt erscheinen hier live.\n\n")
            appendLog(header)
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw failure(String(localized: "Terminal wurde nicht gefunden.")) }
            do { _ = try await NSWorkspace.shared.open([job.script], withApplicationAt: terminal, configuration: config) }
            catch { throw failure(String(localized: "Terminal konnte nicht geöffnet werden: ") + error.localizedDescription) }
            status = String(localized: "Im Terminal-Fenster das Mac-Passwort eingeben. Der USB-Stick wird dort erstellt …")
            cancelRequestedAt = nil; activeJob = job; waitingForTerminal = true
            defer { waitingForTerminal = false; activeJob = nil; DockProgress.clear() }
            var exit: Int32?
            var shown = ""
            let opened = Date()
            while exit == nil {
                // Cancel requested but no reaction: Terminal is most likely still asking for the password.
                if let asked = cancelRequestedAt, Date().timeIntervalSince(asked) > 20, job.output().isEmpty {
                    throw failure(String(localized: "Abgebrochen. Im Terminal-Fenster ist vermutlich noch die Passwortabfrage offen – bitte das Fenster schließen. Auch nach einer Passworteingabe bricht der Vorgang sofort ab; der USB-Stick wurde nicht verändert."))
                }
                // The root command stops within seconds of a cancel request. No status after a minute means the
                // Terminal window was closed and nobody will ever write one – don't wait forever.
                if let asked = cancelRequestedAt, Date().timeIntervalSince(asked) > 60, job.exitStatus() == nil {
                    log = header + USBProgress.clean(job.output())
                    throw failure(String(localized: "Abgebrochen. Das Terminal-Fenster antwortet nicht mehr (vermutlich geschlossen). Der USB-Stick ist möglicherweise unvollständig und muss vor einer weiteren Verwendung neu erstellt oder formatiert werden."))
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                exit = job.exitStatus()
                // Without a cancel request: notice a closed Terminal window (or a script that never started)
                // instead of waiting forever. The status is written before the shell ends, so read it once more.
                if exit == nil, cancelRequestedAt == nil {
                    let running = job.shellRunning()
                    if running == false || (running == nil && Date().timeIntervalSince(opened) > 120 && job.output().isEmpty) {
                        exit = job.exitStatus()
                        if exit == nil {
                            let current = USBProgress.clean(job.output())
                            log = header + current
                            if running == nil { throw failure(String(localized: "Terminal hat die USB-Erstellung nicht gestartet. Der USB-Stick wurde nicht verändert.")) }
                            let touched = current.contains(USBProgress.prepareMarker) || current.contains(USBProgress.startMarker)
                            throw failure(touched
                                ? String(localized: "Das Terminal-Fenster wurde geschlossen, bevor der Vorgang fertig war. Der USB-Stick ist möglicherweise unvollständig und muss vor einer weiteren Verwendung neu erstellt oder formatiert werden.")
                                : String(localized: "Das Terminal-Fenster wurde geschlossen, bevor der Vorgang fertig war. Der USB-Stick wurde nicht verändert."))
                        }
                    }
                }
                // Mirror the Terminal output live: current step, percentage and log.
                let current = job.output()
                if current != shown {
                    shown = current
                    log = header + USBProgress.clean(current)
                    if let live = USBProgress.parse(current) {
                        progress = live.percent
                        status = live.percent.map { "\(live.step) · \(Int($0)) %" } ?? live.step + " …"
                        DockProgress.show(live.percent.map { $0 / 100 })
                    }
                }
            }
            let output = USBProgress.clean(job.output())
            log = header + output
            guard exit == 0 else {
                switch exit {
                case TerminalJob.cancelledExit:
                    throw failure(output.contains(USBProgress.startMarker)
                        ? String(localized: "USB-Erstellung abgebrochen. Der USB-Stick ist unvollständig und muss vor einer weiteren Verwendung neu erstellt oder formatiert werden.\n\n") + output
                        : String(localized: "USB-Erstellung abgebrochen. Der USB-Stick wurde nicht verändert."))
                case TerminalJob.noWriteAccessExit:
                    privacyPane = "Privacy_AllFiles"
                    throw failure(Self.terminalAccessHint + String(localized: "\n\nDie Prüfung erfolgte vor dem Löschen – der USB-Stick wurde nicht verändert."))
                case TerminalJob.targetChangedExit:
                    throw failure(String(localized: "Das Ziel-Laufwerk hat sich vor dem Schreiben geändert. Bitte die USB-Laufwerke aktualisieren und erneut auswählen. Der USB-Stick wurde nicht verändert."))
                default: break
                }
                if output.localizedCaseInsensitiveContains("does not appear to be a valid OS installer") {
                    throw failure(String(localized: "Apple lehnt diesen Installer als unvollständig oder beschädigt ab (253). Bitte unter „Installer lokal“ entfernen und erneut vollständig laden. Der Installer wird nicht automatisch geöffnet.\n\n") + output)
                }
                if output.contains("Operation not permitted") || output.contains(".IAPhysicalMedia") {
                    privacyPane = "Privacy_AllFiles"
                    throw failure(Self.terminalAccessHint + "\n\n" + output)
                }
                if exit == 1 && output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw failure(String(localized: "Die Administratorfreigabe im Terminal ist fehlgeschlagen. Der USB-Stick wurde nicht verändert.\n\n") + output)
                }
                throw failure(output.isEmpty ? String(localized: "USB-Erstellung fehlgeschlagen (Code \(String(exit ?? -1))).") : output)
            }
            progress = 100; status = String(localized: "Bootfähiger USB-Stick ist bereit")
        } catch { status = String(localized: "USB-Erstellung nicht abgeschlossen"); self.error = error.localizedDescription }
    }
    /// Bundles app/system info and the recent log into a text file for bug reports (#9).
    func exportDiagnostics() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "–") (Build \(info?["CFBundleVersion"] as? String ?? "–"))"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var report = """
        OS Studio – Diagnose
        Erstellt: \(ISO8601DateFormatter().string(from: Date()))
        App-Version: \(version)
        macOS: \(os)
        Katalog: \(catalogStatus)
        Lokale Installer: \(localItems.count)

        — Letztes Protokoll —
        """
        report += "\n" + (log.isEmpty ? "(leer)" : log)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OS-Studio-Diagnose.txt"
        panel.allowedContentTypes = [.plainText]
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.data(using: .utf8)?.write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { self.error = String(localized: "Diagnose konnte nicht gespeichert werden: \(error.localizedDescription)") }
    }
    func openPrivacySettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (privacyPane ?? "Privacy_AllFiles"))!
        if !NSWorkspace.shared.open(pane) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "MacOSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

extension StudioModel {
    /// True on Apple silicon, also when this process itself runs translated.
    nonisolated static var hostIsARM: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
}

/// Thread-safe cancel flag shared with detached checksum work.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    func reset() { lock.lock(); flag = false; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
