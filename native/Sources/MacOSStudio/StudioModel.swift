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
    @Published var selectedInstaller = ""
    @Published var selectedDisk = ""
    @Published var selectedMac = ""
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
    @Published var completedPath = ""
    private var command: Command?
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
        refreshLocal()
    }
    var currentMac: MacModel? { models.first { $0.id == selectedMac } }
    var filteredInstallers: [Installer] {
        installers.filter { item in
            (query.isEmpty || "\(item.title) \(item.version) \(item.build)".localizedCaseInsensitiveContains(query)) &&
            (currentMac == nil || currentMac!.supports(item))
        }
    }
    var filteredModels: [MacModel] {
        let words = modelQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return models.filter { mac in
            let text = "\(mac.name) \(mac.year) \(mac.identifiers.joined(separator: " ")) \(mac.cpu)"
            return words.allSatisfy { text.localizedCaseInsensitiveContains($0) }
        }
    }
    var disk: ExternalDisk? { disks.first { $0.id == selectedDisk } }
    var canFlash: Bool { !busy && !loading && !scanning && disk != nil && !selectedInstaller.isEmpty }

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
        path.hasSuffix(".app") && FileManager.default.isExecutableFile(atPath: path + "/Contents/Resources/createinstallmedia")
    }
    func chooseInstaller() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            guard validInstaller(url.path) else { error = "Die App enthält kein ausführbares createinstallmedia."; return }
            selectedInstaller = url.path; extraLocalPaths.insert(url.path); refreshLocal()
            Task { await scanLocal() }
        }
    }
    func scanLocal() async {
        guard !localScanning else { return }
        localScanning = true
        defer { localScanning = false }
        refreshLocal()
        let known = localInstallers
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["/Applications", home.appendingPathComponent("Applications").path,
                     home.appendingPathComponent("Downloads").path, home.appendingPathComponent("Desktop").path]
        let items = await Task.detached(priority: .utility) {
            LocalInstaller.discover(roots: roots, known: known)
        }.value
        localItems = items
        extraLocalPaths.formUnion(items.map(\.path))
        refreshLocal()
    }
    func trashLocal(_ item: LocalInstaller) async {
        guard !busy && !localScanning && localItems.contains(item) else { return }
        busy = true
        localNotice = "Installer wird in den Papierkorb verschoben …"
        do {
            try await Task.detached(priority: .utility) { try item.moveToTrash() }.value
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
    func loadCatalog() async {
        guard !loading && !busy else { return }
        loading = true; catalogStatus = "Apple-Katalog wird geprüft … maximal 90 Sekunden"
        defer { loading = false }
        do {
            let result = try await Command().run("/usr/sbin/softwareupdate", ["--list-full-installers"], timeout: 90)
            guard !result.timedOut else { throw failure("Apple antwortet nicht. Verbindung prüfen und erneut laden.") }
            guard result.status == 0 else { throw failure(result.output) }
            let items = Installer.parse(result.output)
            guard !items.isEmpty else { throw failure("Apple bietet für diesen Mac keine Installer an.\n" + result.output) }
            installers = items
            catalogStatus = "\(items.count) Versionen für diesen Mac abrufbar · Apple-Katalog"
        } catch { catalogStatus = "Katalog konnte nicht geladen werden"; self.error = error.localizedDescription }
    }
    func download(_ item: Installer) async {
        guard !busy && !loading else { return }
        guard Installer.validVersion(item.version) else { error = "Bitte eine Version wie 15.7.2 eingeben."; return }
        let free = ((try? FileManager.default.attributesOfFileSystem(forPath: "/Applications")[.systemFreeSize]) as? NSNumber)?.doubleValue ?? 0
        guard free > max(item.bytes * 2 + 5e9, 20e9) else { error = "Nicht genügend freier Speicher für Download und Entpacken."; return }
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
        defer { monitor.cancel(); command = nil; busy = false; mbits = nil }
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
            guard let path = named.count == 1 ? named.first : (changed.count == 1 ? changed.first : nil) else {
                throw failure("Apple hat den Vorgang beendet, aber kein passender bootfähiger Installer wurde gefunden.")
            }
            completedPath = path; selectedInstaller = path; progress = 100; amount = total > 0 ? total : nil
            status = "Installer geladen und geprüft"
        } catch { status = "Download fehlgeschlagen"; self.error = error.localizedDescription }
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
    }
    func cancel() { guard !flashing else { return }; status = "Download wird abgebrochen …"; command?.cancel() }
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
    func flash() async {
        guard canFlash, let target = disk, validInstaller(selectedInstaller) else { return }
        busy = true; flashing = true; progress = nil; amount = nil; mbits = nil; total = 0
        completedPath = ""
        activeTitle = "USB-Stick erstellen"; log = ""; status = "Ziel-Laufwerk erneut prüfen …"
        defer { busy = false; flashing = false }
        do {
            let checked = try await diskInfo(target.identifier)
            guard checked == target else { throw failure("Das Ziel-Laufwerk hat sich geändert. Bitte erneut auswählen.") }
            let tool = selectedInstaller + "/Contents/Resources/createinstallmedia"
            guard validInstaller(selectedInstaller) else { throw failure("Installer nicht mehr verfügbar.") }
            // Direct, escaped command; no writable temporary root shell script.
            // Recheck UUID and Internal under elevation immediately before invoking Apple's tool.
            let lookup = "/usr/sbin/diskutil info -plist " + shellQuote(target.identifier)
            let checkUUID = "$(" + lookup + " | /usr/bin/plutil -extract VolumeUUID raw -o - -)"
            let checkInternal = "$(" + lookup + " | /usr/bin/plutil -extract Internal raw -o - -)"
            let checkMount = "$(" + lookup + " | /usr/bin/plutil -extract MountPoint raw -o - -)"
            let shell = "test \"" + checkUUID + "\" = " + shellQuote(target.uuid) + " && test \"" + checkInternal + "\" = false && test \"" + checkMount + "\" = " + shellQuote(target.mount) + " && " + shellQuote(tool) + " --volume " + shellQuote(target.mount) + " --nointeraction"
            status = "Administratorfreigabe bestätigen. Anschließend wird der USB-Stick erstellt …"
            appendLog("Installer: \(selectedInstaller)\nZiel: \(target.name) · \(target.identifier) · \(target.mount)\nApple liefert die Ausgabe dieses administrativen Vorgangs nach Abschluss.\n")
            let result = try await Command().run("/usr/bin/osascript", ["-e", "do shell script " + appleScriptQuote(shell) + " with administrator privileges"], timeout: .greatestFiniteMagnitude)
            appendLog(result.output)
            guard result.status == 0 else { throw failure(result.output.isEmpty ? "USB-Erstellung fehlgeschlagen." : result.output) }
            progress = 100; status = "Bootfähiger USB-Stick ist bereit"
        } catch { status = "USB-Erstellung nicht abgeschlossen"; self.error = error.localizedDescription }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "MacOSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
