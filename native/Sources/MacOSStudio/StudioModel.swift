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
    @Published var status = "Bereit"
    @Published var catalogStatus = "Apple-Katalog noch nicht geladen"
    @Published var progress: Double?
    @Published var amount: Double?
    @Published var mbits: Double?
    @Published var total: Double = 0
    @Published var activeTitle = ""
    @Published var log = ""
    @Published var error: String?
    /// Privacy pane anchor to offer with the current error, if any.
    @Published var privacyPane: String?
    static let terminalAccessHint = "macOS hat Terminal den Schreibzugriff auf den USB-Stick verweigert (250). Bitte unter Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff „Terminal“ aktivieren, Terminal beenden und die USB-Erstellung erneut starten. Alternativ genügt bei „Dateien und Ordner“ für Terminal der Zugriff auf „Wechselmedien“."
    /// Set while the Terminal job runs; the user can cancel it from the app.
    @Published var waitingForTerminal = false
    @Published private(set) var cancelRequestedAt: Date?
    private var activeJob: TerminalJob?
    func cancelTerminalJob() {
        guard let job = activeJob, cancelRequestedAt == nil else { return }
        job.requestCancel(); cancelRequestedAt = Date()
        status = "Abbruch angefordert …"
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
        if log.count > 60_000 { log = String(log.suffix(50_000)) }
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
            do { try fileAccess.remember(url) } catch { self.error = "Speicherort konnte nicht dauerhaft gespeichert werden: " + error.localizedDescription; return }
            guard FileManager.default.isExecutableFile(atPath: url.path + "/Contents/Resources/createinstallmedia") else {
                error = "Die App enthält kein ausführbares createinstallmedia."; return
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
        panel.message = "Ordner für die Installer-Suche freigeben. Die Auswahl wird für kommende Starts gespeichert."
        panel.prompt = "Ordner merken"
        if panel.runModal() == .OK, let url = panel.url {
            do { try fileAccess.remember(url); Task { await scanLocal() } }
            catch { self.error = "Ordnerauswahl konnte nicht gespeichert werden: " + error.localizedDescription }
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
        localNotice = "„\(item.name)“ wird geprüft …"
        let path = item.path
        let fresh = await Task.detached(priority: .userInitiated) { LocalInstaller.inspect(path) }.value
        guard let fresh else { localNotice = "„\(item.name)“ ist nicht mehr auffindbar. Liste aktualisieren."; return }
        if let issue = fresh.preparationIssue {
            localNotice = "„\(item.name)“: \(issue)"
        } else {
            let size = fresh.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "unbekannt"
            localNotice = "„\(item.name)“: OK – vollständige Installationsdaten vorhanden (\(size)). Bereit für die USB-Erstellung."
        }
    }
    func trashLocal(_ item: LocalInstaller) async {
        guard !busy && !localScanning && localItems.contains(item) else { return }
        busy = true
        localNotice = "Installer wird in den Papierkorb verschoben …"
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
                guard !FileManager.default.fileExists(atPath: item.path) else { throw failure("Der Installer wurde nicht verschoben. Bitte erneut prüfen.") }
            }
            extraLocalPaths.remove(item.path)
            if selectedInstaller == item.path { selectedInstaller = "" }
            if completedPath == item.path { completedPath = "" }
            localItems.removeAll { $0.path == item.path }
            refreshLocal()
            localNotice = "„\(item.name)“ wurde in den Papierkorb verschoben. Speicher wird erst beim Leeren des Papierkorbs freigegeben."
        } catch {
            localNotice = "Installer konnte nicht entfernt werden."
            self.error = error.localizedDescription
        }
        busy = false
    }
    /// Root-owned installers: first let Finder trash them (it asks for the password itself), then fall back to
    /// handing ownership to the user. macOS "App Management" can block both for apps in /Applications.
    private func trashWithAdministrator(_ item: LocalInstaller) async throws {
        localNotice = "Finder verschiebt den Installer in den Papierkorb – bitte ggf. das Passwort eingeben …"
        let script = try await Task.detached(priority: .utility) { try item.finderTrashScript() }.value
        let finder = try await Command().run("/usr/bin/osascript", ["-e", script], timeout: .greatestFiniteMagnitude)
        if finder.status == 0 && !FileManager.default.fileExists(atPath: item.path) { return }
        if finder.output.contains("(-128)") { throw failure("Entfernen abgebrochen. Der Installer bleibt erhalten.") }
        let automationDenied = finder.output.contains("(-1743)")
        localNotice = "Administratorfreigabe zum Verschieben in den Papierkorb erforderlich …"
        let shell = try await Task.detached(priority: .utility) {
            try item.authorizedOwnershipCommand(owner: getuid())
        }.value
        let result = try await Command().run("/usr/bin/osascript",
            ["-e", "do shell script " + appleScriptQuote(shell) + " with administrator privileges"], timeout: .greatestFiniteMagnitude)
        if result.output.contains("(-128)") { throw failure("Entfernen abgebrochen. Der Installer bleibt erhalten.") }
        guard result.status == 0 else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            if automationDenied {
                privacyPane = "Privacy_Automation"
                throw failure("macOS hat OS Studio die Steuerung des Finders verweigert. Bitte unter Systemeinstellungen → Datenschutz & Sicherheit → Automation bei „OS Studio“ den Finder erlauben und erneut löschen.\n\nAlternativ den im Finder markierten Installer selbst in den Papierkorb ziehen.")
            }
            privacyPane = result.output.contains("Operation not permitted") ? "Privacy_AppBundles" : nil
            throw failure("macOS schützt den Installer vor Änderungen durch andere Apps („App-Verwaltung“). Der Installer ist jetzt im Finder markiert: Einfach in den Papierkorb ziehen und mit dem Passwort bestätigen.\n\nAlternativ unter Systemeinstellungen → Datenschutz & Sicherheit → App-Verwaltung „OS Studio“ aktivieren und erneut löschen.")
        }
        // Ownership changed; revalidate the same bundle and trash it as the user.
        try await Task.detached(priority: .utility) {
            guard let current = LocalInstaller.inspect(item.path), current.path == item.path, current.bytes == item.bytes else {
                throw NSError(domain: "LocalInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "Der Installer wurde verändert. Bitte die Liste aktualisieren."])
            }
            try current.moveToTrash()
        }.value
    }
    func loadCatalog() async {
        guard !loading && !busy else { return }
        loading = true; catalogStatus = "Apple-Katalog wird geprüft … maximal 90 Sekunden"
        defer { loading = false }
        async let offeredResult = Self.offeredInstallers()
        async let catalogResult = Self.catalogInstallers()
        let (offered, catalog) = await (offeredResult, catalogResult)
        let merged = AppleCatalog.merge(offered: (try? offered.get()) ?? [], catalog: (try? catalog.get()) ?? [])
        guard !merged.isEmpty else {
            catalogStatus = "Katalog konnte nicht geladen werden"
            let reasons = [offered, catalog].compactMap { result -> String? in
                if case .failure(let problem) = result { return problem.localizedDescription }; return nil
            }
            error = reasons.isEmpty ? "Apple bietet keine Installer an." : reasons.joined(separator: "\n\n")
            return
        }
        installers = merged
        let extra = merged.filter { !$0.offeredForThisMac }.count
        catalogStatus = "\(merged.count) Versionen abrufbar · Apple-Katalog" + (extra > 0 ? " · \(extra) davon nicht für diesen Mac, Download als Apple-Paket für andere Macs" : "")
        if case .failure = catalog, extra == 0 { catalogStatus += " · vollständiger Katalog nicht erreichbar" }
    }
    private nonisolated static func offeredInstallers() async -> Result<[Installer], Error> {
        do {
            let result = try await Command().run("/usr/sbin/softwareupdate", ["--list-full-installers"], timeout: 90)
            guard !result.timedOut else { throw failure("Apple antwortet nicht. Verbindung prüfen und erneut laden.") }
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
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw failure("Apple-Katalog nicht erreichbar.") }
            let products = AppleCatalog.products(fromCatalog: try Gzip.decompress(data))
            let items = await withTaskGroup(of: Installer?.self) { group in
                for product in products {
                    group.addTask {
                        guard let (text, _) = try? await URLSession.shared.data(for: URLRequest(url: product.distribution, timeoutInterval: 30)),
                              let info = AppleCatalog.describe(distribution: String(decoding: text, as: UTF8.self)) else { return nil }
                        return Installer(title: info.title, version: info.version, build: info.build, bytes: product.bytes,
                                         packageURL: product.package, offeredForThisMac: false)
                    }
                }
                var collected: [Installer] = []
                for await item in group { if let item { collected.append(item) } }
                return collected
            }
            // Apple occasionally lists the same build twice; keep one.
            var seen = Set<String>()
            return .success(items.filter { seen.insert($0.version + $0.build).inserted })
        } catch { return .failure(error) }
    }
    private nonisolated static func failure(_ message: String) -> NSError { NSError(domain: "MacOSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func download(_ item: Installer) async {
        guard !busy && !loading else { return }
        guard Installer.validVersion(item.version) else { error = "Bitte eine Version wie 15.7.2 eingeben."; return }
        busy = true
        status = "Vorhandene Installer werden geprüft …"
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
            status = "Passender Installer bereits vorhanden – kein Download nötig"
            log = "Vorhandener Installer: \(existing.path)\n"
            error = "Dieser Installer ist bereits vorhanden:\n\(existing.path)\n\nVersion und Installationsdaten wurden erkannt. Er wurde für die USB-Erstellung ausgewählt; ein erneuter Download ist nicht nötig."
            return
        }
        // A manual request is titled only "macOS" and would match every installer; skip the series check.
        let manual = item.build == "Manuell"
        if !manual, let existing = found.first(where: { $0.name.localizedCaseInsensitiveContains(item.title) }) {
            status = "Vorhandenen Installer prüfen"
            if let issue = existing.preparationIssue {
                error = "\(existing.path)\n\n\(issue)\nBitte unter „Installer lokal“ in den Papierkorb verschieben und danach erneut laden."
            } else {
                error = "Ein Installer dieser macOS-Reihe ist bereits vorhanden:\n\(existing.path)\n\nDie gewünschte Version \(item.version) (\(item.build)) konnte nicht bestätigt werden. Bitte unter „Installer lokal“ prüfen. Für einen neuen Download den vorhandenen Installer zuerst an einen anderen Ort verschieben oder in den Papierkorb legen."
            }
            return
        }
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: "/Applications")[.systemFreeSize]) as? NSNumber)?.doubleValue ?? 0
        guard free > max(item.bytes * 2 + 5e9, 20e9) else { error = "Nicht genügend freier Speicher für Download und Entpacken."; return }
        if !item.offeredForThisMac, item.packageURL != nil { await downloadPackage(item); return }
        busy = true; flashing = false; completedPath = ""; log = ""; activeTitle = item.title + " " + item.version
        total = item.bytes; amount = nil; mbits = nil; progress = nil
        metrics.reset(); lastSample = nil; lastProgress = Date(); buffer = ""; stopReason = nil
        status = "Apple prüft die Verfügbarkeit …"
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
                    self.stopReason = self.lastSample == nil ? "Apple meldet nach 3 Minuten keinen Downloadfortschritt. Katalog neu laden und erneut versuchen." : "Seit 15 Minuten kein Fortschritt. Verbindung und Speicher prüfen."
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
            if result.cancelled { status = "Download abgebrochen"; return }
            guard result.status == 0 && !result.timedOut else { throw failure(String(result.output.suffix(1800))) }
            refreshLocal()
            let changed = localInstallers.filter { before[$0] == nil || before[$0] != modification($0) }
            let named = localInstallers.filter { URL(fileURLWithPath: $0).lastPathComponent.localizedCaseInsensitiveContains(item.title) }
            let candidate = manual ? (changed.count == 1 ? changed.first : nil)
                : (named.count == 1 ? named.first : (changed.count == 1 ? changed.first : nil))
            guard let path = candidate else {
                throw failure("Apple hat den Vorgang beendet, aber kein passender Installer mit Installationsdaten wurde gefunden. Unter „Installer lokal“ kannst du unvollständige Downloads prüfen und entfernen.")
            }
            completedPath = path; selectedInstaller = path; progress = 100; amount = total > 0 ? total : nil
            status = "Installer geladen und geprüft"
        } catch { status = "Download fehlgeschlagen"; self.error = error.localizedDescription }
    }
    /// Catalog-only installers: download Apple's InstallAssistant.pkg, verify it and let macOS' installer
    /// create "Install macOS ….app" in /Applications. Works on Macs that cannot run this macOS themselves.
    private func downloadPackage(_ item: Installer) async {
        guard let url = item.packageURL else { return }
        busy = true; flashing = false; completedPath = ""; log = ""; activeTitle = item.title + " " + item.version
        total = item.bytes; amount = nil; mbits = nil; progress = 0
        status = "Apple-Paket wird geladen …"
        let downloader = PackageDownload(); packageDownload = downloader
        defer { packageDownload = nil; busy = false; mbits = nil }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.appletools.macosstudio/Packages", isDirectory: true)
        let package = folder.appendingPathComponent("InstallAssistant-\(item.build).pkg")
        defer { try? FileManager.default.removeItem(at: package) }
        appendLog("Quelle: \(url.absoluteString)\n")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            packageSample = (ProcessInfo.processInfo.systemUptime, 0)
            _ = try await downloader.run(url, to: package) { [weak self] written, expected in
                Task { @MainActor in self?.packageProgress(written: written, expected: expected) }
            }
            mbits = nil; progress = 95
            let size = ((try? FileManager.default.attributesOfItem(atPath: package.path)[.size]) as? NSNumber)?.doubleValue ?? 0
            guard item.bytes <= 0 || size == item.bytes else {
                throw failure("Das geladene Paket ist unvollständig (\(Int64(size)) statt \(Int64(item.bytes)) Bytes). Bitte erneut laden.")
            }
            status = "Apple-Signatur wird geprüft …"
            let signature = try await Command().run("/usr/sbin/pkgutil", ["--check-signature", package.path], timeout: 600)
            appendLog(signature.output)
            guard signature.status == 0, signature.output.contains("signed Apple Software") else {
                throw failure("Das Paket ist nicht von Apple signiert und wird nicht installiert.\n\n" + signature.output)
            }
            status = "Installer-App wird erstellt – bitte Administratorpasswort eingeben …"; progress = 97
            let before = Dictionary(uniqueKeysWithValues: localInstallers.map { ($0, modification($0)) })
            let shell = "/usr/sbin/installer -pkg " + shellQuote(package.path) + " -target /"
            let result = try await Command().run("/usr/bin/osascript",
                ["-e", "do shell script " + appleScriptQuote(shell) + " with administrator privileges"], timeout: 3 * 3600)
            appendLog(result.output)
            if result.output.contains("(-128)") { status = "Abgebrochen"; return }
            guard result.status == 0 else { throw failure("Apples Installer konnte die Installer-App nicht erstellen.\n\n" + String(result.output.suffix(1800))) }
            refreshLocal()
            let changed = localInstallers.filter { before[$0] == nil || before[$0] != modification($0) }
            let found = LocalInstaller.discover(roots: ["/Applications"], known: changed)
            guard let installed = found.first(where: { $0.matches(item) }) ?? (changed.count == 1 ? LocalInstaller.inspect(changed[0]) : nil) else {
                throw failure("Das Paket wurde installiert, aber keine passende Installer-App wurde in /Applications gefunden.")
            }
            localItems = found
            completedPath = installed.path; selectedInstaller = installed.path; progress = 100; amount = total
            status = "Installer geladen und geprüft"
        } catch {
            if (error as? URLError)?.code == .cancelled { status = "Download abgebrochen"; return }
            status = "Download fehlgeschlagen"; self.error = error.localizedDescription
        }
    }
    private var packageSample: (time: TimeInterval, bytes: Int64) = (0, 0)
    private func packageProgress(written: Int64, expected: Int64) {
        guard busy else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - packageSample.time >= 1 else { return }
        mbits = Double(written - packageSample.bytes) * 8 / (now - packageSample.time) / 1_000_000
        packageSample = (now, written)
        let size = expected > 0 ? Double(expected) : total
        if size > 0 { total = size; progress = min(95, Double(written) / size * 95) }
        amount = Double(written); status = "Apple-Paket wird geladen"
    }
    private func modification(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date ?? .distantPast
    }
    private func consume(_ text: String) {
        appendLog(text)
        buffer += text
        if let sample = ProgressSample.parse(buffer) { update(sample) }
        if buffer.count > 2048 { buffer = String(buffer.suffix(512)) }
    }
    private func update(_ sample: ProgressSample) {
        guard sample != lastSample else { return }
        if Date().timeIntervalSince(lastProgress) > 15 { metrics.reset() }
        lastSample = sample; lastProgress = Date()
        progress = min(99.9, sample.percent)
        let values = metrics.update(sample, total: total, time: ProcessInfo.processInfo.systemUptime)
        amount = values.bytes; mbits = values.mbits
        status = sample.phase == "downloading" ? "Installer wird geladen" : "Installer laden und vorbereiten"
        DockProgress.show(progress.map { $0 / 100 })
    }
    func cancel() { guard !flashing else { return }; status = "Download wird abgebrochen …"; command?.cancel(); packageDownload?.cancel() }
    func detectMac() async {
        guard !detectingMac else { return }
        detectingMac = true
        defer { detectingMac = false }
        do {
            let result = try await Command().run("/usr/sbin/sysctl", ["-n", "hw.model"], timeout: 5)
            let id = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let model = models.first(where: { $0.identifiers.contains(id) }) {
                modelQuery = model.name; selectedMac = model.id; detectedMacID = model.id
            } else { modelQuery = id; error = "\(id) ist in der übernommenen Modelldatenbank nicht enthalten." }
        } catch { self.error = error.localizedDescription }
    }
    func scanDisks() async {
        guard !scanning && !busy else { return }
        scanning = true
        defer { scanning = false }
        refreshLocal()
        do {
            let result = try await Command().run("/usr/sbin/diskutil", ["list", "-plist", "external"], timeout: 10)
            guard result.status == 0 && !result.timedOut else { throw failure("Laufwerkssuche fehlgeschlagen oder Zeitlimit erreicht.") }
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
              let disk = ExternalDisk.validated(plist) else { throw failure("Kein geeignetes externes USB-Volume.") }
        return disk
    }
    private func diskPlist(_ identifier: String) async throws -> [String: Any] {
        let result = try await Command().run("/usr/sbin/diskutil", ["info", "-plist", identifier], timeout: 5)
        guard result.status == 0, !result.timedOut,
              let info = try PropertyListSerialization.propertyList(from: Data(result.output.utf8), format: nil) as? [String: Any] else { throw failure("Laufwerksinformationen konnten nicht gelesen werden.") }
        return info
    }
    func flash() async {
        guard canFlash, let target = disk, validInstaller(selectedInstaller) else { return }
        busy = true; flashing = true; progress = nil; amount = nil; mbits = nil; total = 0
        privacyPane = nil
        completedPath = ""
        activeTitle = "USB-Stick erstellen"; log = ""; status = "Ziel-Laufwerk erneut prüfen …"
        defer { busy = false; flashing = false }
        do {
            let checked = try await diskInfo(target.identifier)
            guard checked == target else { throw failure("Das Ziel-Laufwerk hat sich geändert. Bitte erneut auswählen.") }
            let tool = selectedInstaller + "/Contents/Resources/createinstallmedia"
            if let issue = LocalInstaller.preparationIssue(at: selectedInstaller) { throw failure(issue) }
            // The stick must hold the whole installer; check before anything is erased.
            status = "Speicherplatz auf dem USB-Stick prüfen …"
            let installerPath = selectedInstaller
            let installerBytes = await Task.detached(priority: .userInitiated) { LocalInstaller.inspect(installerPath)?.bytes }.value
            let required = Self.requiredUSBBytes(installerBytes: installerBytes)
            guard target.bytes >= required else {
                throw failure(String(format: "Der USB-Stick ist zu klein: %.1f GB vorhanden, für diesen Installer werden mindestens %.0f GB benötigt. Der USB-Stick wurde nicht verändert.", target.bytes / 1e9, (required / 1e9).rounded(.up)))
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
                      let store = stores[0]["DeviceIdentifier"] as? String else { throw failure("APFS-Ziel konnte nicht sicher zugeordnet werden.") }
                let physical = try await diskPlist(store)
                guard let plan = USBPreparation(target: target, container: container, storeInfo: physical) else {
                    throw failure("Dieser APFS-Container enthält weitere Volumes oder lässt sich keinem einzelnen externen USB-Speicher zuordnen. Automatische Formatierung wurde gestoppt, um andere Daten zu schützen.")
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
                                           tool: tool, volume: volume)
            try job.write(rootCommand: shell, headline: "OS Studio – bootfähigen USB-Stick erstellen\nInstaller: \(selectedInstaller)\nZiel: \(target.name) (\(target.identifier)) – wird gelöscht")
            let header = "Installer: \(selectedInstaller)\nZiel: \(target.name) · \(target.identifier) · \(target.mount)\nDer Vorgang läuft im Terminal-Fenster; Schritte und Fortschritt erscheinen hier live.\n\n"
            appendLog(header)
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw failure("Terminal wurde nicht gefunden.") }
            do { _ = try await NSWorkspace.shared.open([job.script], withApplicationAt: terminal, configuration: config) }
            catch { throw failure("Terminal konnte nicht geöffnet werden: " + error.localizedDescription) }
            status = "Im Terminal-Fenster das Mac-Passwort eingeben. Der USB-Stick wird dort erstellt …"
            cancelRequestedAt = nil; activeJob = job; waitingForTerminal = true
            defer { waitingForTerminal = false; activeJob = nil; DockProgress.clear() }
            var exit: Int32?
            var shown = ""
            while exit == nil {
                // Cancel requested but no reaction: Terminal is most likely still asking for the password.
                if let asked = cancelRequestedAt, Date().timeIntervalSince(asked) > 20, job.output().isEmpty {
                    throw failure("Abgebrochen. Im Terminal-Fenster ist vermutlich noch die Passwortabfrage offen – bitte das Fenster schließen. Auch nach einer Passworteingabe bricht der Vorgang sofort ab; der USB-Stick wurde nicht verändert.")
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                exit = job.exitStatus()
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
                        ? "USB-Erstellung abgebrochen. Der USB-Stick ist unvollständig und muss vor einer weiteren Verwendung neu erstellt oder formatiert werden.\n\n" + output
                        : "USB-Erstellung abgebrochen. Der USB-Stick wurde nicht verändert.")
                case TerminalJob.noWriteAccessExit:
                    privacyPane = "Privacy_AllFiles"
                    throw failure(Self.terminalAccessHint + "\n\nDie Prüfung erfolgte vor dem Löschen – der USB-Stick wurde nicht verändert.")
                case TerminalJob.targetChangedExit:
                    throw failure("Das Ziel-Laufwerk hat sich vor dem Schreiben geändert. Bitte die USB-Laufwerke aktualisieren und erneut auswählen. Der USB-Stick wurde nicht verändert.")
                default: break
                }
                if output.localizedCaseInsensitiveContains("does not appear to be a valid OS installer") {
                    throw failure("Apple lehnt diesen Installer als unvollständig oder beschädigt ab (253). Bitte unter „Installer lokal“ entfernen und erneut vollständig laden. Der Installer wird nicht automatisch geöffnet.\n\n" + output)
                }
                if output.contains("Operation not permitted") || output.contains(".IAPhysicalMedia") {
                    privacyPane = "Privacy_AllFiles"
                    throw failure(Self.terminalAccessHint + "\n\n" + output)
                }
                if exit == 1 && output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw failure("Die Administratorfreigabe im Terminal ist fehlgeschlagen. Der USB-Stick wurde nicht verändert.\n\n" + output)
                }
                throw failure(output.isEmpty ? "USB-Erstellung fehlgeschlagen (Code \(exit ?? -1))." : output)
            }
            progress = 100; status = "Bootfähiger USB-Stick ist bereit"
        } catch { status = "USB-Erstellung nicht abgeschlossen"; self.error = error.localizedDescription }
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
        } catch { self.error = "Diagnose konnte nicht gespeichert werden: \(error.localizedDescription)" }
    }
    func openPrivacySettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (privacyPane ?? "Privacy_AllFiles"))!
        if !NSWorkspace.shared.open(pane) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "MacOSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
