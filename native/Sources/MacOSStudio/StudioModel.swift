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
    var filteredInstallers: [Installer] {
        installers.filter { item in
            (query.isEmpty || "\(item.title) \(item.version) \(item.build)".localizedCaseInsensitiveContains(query)) &&
            (currentMac == nil || currentMac!.supports(item))
        }
    }
    var filteredModels: [MacModel] {
        models.filter { $0.matches(query: modelQuery) }
    }
    var serialSearchAvailable: Bool { MacModel.isSerialQuery(modelQuery) && filteredModels.isEmpty }
    private var lastSerialLookup = ""
    func searchSerial() async {
        guard serialSearchAvailable && !detectingMac else { return }
        let serial = modelQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard serial != lastSerialLookup else { return }
        lastSerialLookup = serial
        guard !Task.isCancelled, modelQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == serial else { lastSerialLookup = ""; return }
        // Apple provides the public serial lookup; do not guess randomized serials.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serial, forType: .string)
        NSWorkspace.shared.open(URL(string: "https://checkcoverage.apple.com/")!)
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
    func trashLocal(_ item: LocalInstaller) async {
        guard !busy && !localScanning && localItems.contains(item) else { return }
        busy = true
        localNotice = "Installer wird in den Papierkorb verschoben …"
        do {
            do {
                try await Task.detached(priority: .utility) { try item.moveToTrash() }.value
            } catch {
                let problem = error as NSError
                guard problem.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(problem.code) else { throw error }
                localNotice = "Administratorfreigabe zum Verschieben in den Papierkorb erforderlich …"
                let shell = try await Task.detached(priority: .utility) {
                    try item.authorizedOwnershipCommand(owner: getuid())
                }.value
                let result = try await Command().run("/usr/bin/osascript",
                    ["-e", "do shell script " + appleScriptQuote(shell) + " with administrator privileges"], timeout: .greatestFiniteMagnitude)
                guard result.status == 0 else {
                    throw failure(result.output.contains("(-128)") ? "Entfernen abgebrochen. Der Installer bleibt erhalten." : "Installer konnte mit Administratorfreigabe nicht für den Papierkorb freigegeben werden.\n" + result.output)
                }
                // Ownership changed; revalidate the same bundle and trash it as the user.
                try await Task.detached(priority: .utility) {
                    guard let current = LocalInstaller.inspect(item.path), current.path == item.path, current.bytes == item.bytes else {
                        throw NSError(domain: "LocalInstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "Der Installer wurde verändert. Bitte die Liste aktualisieren."])
                    }
                    try current.moveToTrash()
                }.value
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
            let candidate = manual ? (changed.count == 1 ? changed.first : nil)
                : (named.count == 1 ? named.first : (changed.count == 1 ? changed.first : nil))
            guard let path = candidate else {
                throw failure("Apple hat den Vorgang beendet, aber kein passender Installer mit Installationsdaten wurde gefunden. Unter „Installer lokal“ kannst du unvollständige Downloads prüfen und entfernen.")
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
            try job.write(rootCommand: shell, headline: "macOS Studio – bootfähigen USB-Stick erstellen\nInstaller: \(selectedInstaller)\nZiel: \(target.name) (\(target.identifier)) – wird gelöscht")
            let header = "Installer: \(selectedInstaller)\nZiel: \(target.name) · \(target.identifier) · \(target.mount)\nDer Vorgang läuft im Terminal-Fenster; Schritte und Fortschritt erscheinen hier live.\n\n"
            appendLog(header)
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { throw failure("Terminal wurde nicht gefunden.") }
            do { _ = try await NSWorkspace.shared.open([job.script], withApplicationAt: terminal, configuration: config) }
            catch { throw failure("Terminal konnte nicht geöffnet werden: " + error.localizedDescription) }
            status = "Im Terminal-Fenster das Mac-Passwort eingeben. Der USB-Stick wird dort erstellt …"
            cancelRequestedAt = nil; activeJob = job; waitingForTerminal = true
            defer { waitingForTerminal = false; activeJob = nil }
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
    func openPrivacySettings() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (privacyPane ?? "Privacy_AllFiles"))!
        if !NSWorkspace.shared.open(pane) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "MacOSStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
