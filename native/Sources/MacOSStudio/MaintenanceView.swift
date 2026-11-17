import AppKit
import SwiftUI
import StudioCore

/// Runs the maintenance tools (Spotlight/LaunchServices repair, deleting old Time Machine backups) as root commands
/// in Terminal and mirrors their progress. Shared, so quitting and app updates can wait for a running job.
@MainActor final class MaintenanceStore: ObservableObject {
    static let shared = MaintenanceStore()

    enum Tool { case repair, timeMachine }
    @Published private(set) var running: Tool?
    @Published var status = ""
    @Published var log = ""
    @Published var progress: Double?
    @Published var message: String?
    @Published var repairFinished = false
    @Published var confirmRepair = false
    @Published var confirmDelete = false

    @Published var databases: [URL] = []
    @Published var selectedDatabase: URL?
    @Published var machines: [TimeMachineBackups.Machine] = []
    @Published var selectedMachine = ""
    @Published var listing = false
    @Published var accessDenied = false
    @Published var listError: String?

    private var job: TerminalJob?
    private var cancelRequested = false
    var working: Bool { running != nil }

    // MARK: Spotlight & LaunchServices

    func repair() async {
        guard running == nil else { return }
        repairFinished = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macOSStudio-Spotlight-" + UUID().uuidString)
        let ok = await run(.repair, name: String(localized: "Spotlight reparieren"),
                           headline: String(localized: "OS Studio – LaunchServices und Spotlight reparieren"),
                           command: SpotlightRepair.rootCommand(cancelFile: directory.appendingPathComponent("cancel")), directory: directory) { [weak self] output in
            guard let self, let step = SpotlightRepair.step(in: output) else { return }
            let names = [String(localized: "LaunchServices-Datenbank wird neu aufgebaut"),
                         String(localized: "Spotlight-Index wird zurückgesetzt"),
                         String(localized: "Dock, Finder und Menüleiste werden neu gestartet")]
            self.status = "\(step)/3 · " + names[min(max(step, 1), 3) - 1]
            self.progress = Double(step - 1) / 3
        }
        if ok { repairFinished = true; status = String(localized: "Reparatur abgeschlossen. Bitte den Mac jetzt neu starten.") }
    }

    // MARK: Time Machine

    func refreshDatabases() {
        databases = TimeMachineBackups.databases()
        if let selected = selectedDatabase, databases.contains(selected) { } else { selectedDatabase = databases.first }
        loadMachines()
    }

    func loadMachines() {
        machines = []; selectedMachine = ""; accessDenied = false; listError = nil
        guard let database = selectedDatabase else { return }
        listing = true
        Task {
            let result: Result<[TimeMachineBackups.Machine], Error> = await Task.detached(priority: .userInitiated) {
                do { return .success(try TimeMachineBackups.machines(in: database)) } catch { return .failure(error) }
            }.value
            guard selectedDatabase == database else { return }
            listing = false
            switch result {
            case .success(let found):
                machines = found
                if found.isEmpty { listError = String(localized: "Auf diesem Laufwerk sind keine Rechner-Ordner.") }
            case .failure(let error):
                if TimeMachineBackups.isAccessDenied(error) { accessDenied = true } else { listError = error.localizedDescription }
            }
        }
    }

    func volumeName(_ database: URL) -> String {
        let volume = database.deletingLastPathComponent()
        return (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? volume.lastPathComponent
    }
    private func freeBytes(_ database: URL) -> Int64? {
        (try? database.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map(Int64.init)
    }

    func deleteSelected() async {
        guard running == nil, let database = selectedDatabase,
              let machine = machines.first(where: { $0.name == selectedMachine }) else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macOSStudio-TM-" + UUID().uuidString)
        guard let command = TimeMachineBackups.deleteCommand(database: database, machine: machine.name,
                                                             cancelFile: directory.appendingPathComponent("cancel")) else { return }
        let startFree = freeBytes(database)
        let ok = await run(.timeMachine, name: String(localized: "Time-Machine-Backups löschen"),
                           headline: String(localized: "OS Studio – Time-Machine-Backups löschen\nRechner: \(machine.name) (\(machine.backups) Backups)\nLaufwerk: \(volumeName(database)) – wird endgültig gelöscht"),
                           command: command, directory: directory) { [weak self] output in
            guard let self else { return }
            let live = TimeMachineBackups.progress(in: output)
            if live.noAccess { return }
            var freed = ""
            if let startFree, let now = self.freeBytes(database) {
                freed = " · " + String(localized: "\(String(format: "%.1f", Double(max(0, now - startFree)) / 1e9)) GB freigegeben")
            }
            if live.cleaningUp { self.status = String(localized: "Restordner wird aufgeräumt …") + freed }
            else if live.total > 0 { self.status = String(localized: "Backup \(live.done) von \(live.total)") + (live.current.map { " · \($0)" } ?? "") + freed }
            self.progress = live.fraction
        }
        if ok {
            var freed = ""
            if let startFree, let now = freeBytes(database) { freed = String(format: "%.1f", Double(max(0, now - startFree)) / 1e9) }
            status = String(localized: "Fertig: „\(machine.name)“ gelöscht.") + (freed.isEmpty ? "" : " " + String(localized: "\(freed) GB freigegeben."))
        } else if TimeMachineBackups.progress(in: log).noAccess {
            message = String(localized: "Terminal hat keinen Zugriff auf die Time-Machine-Backups. Erlaube Terminal unter Systemeinstellungen › Datenschutz & Sicherheit › Festplattenvollzugriff, beende Terminal und versuche es erneut. Es wurde nichts gelöscht.")
        }
        loadMachines()
    }

    func cancel() {
        cancelRequested = true
        job?.requestCancel()
        status = String(localized: "Wird abgebrochen …")
    }

    // MARK: Terminal job

    /// Opens the root command in Terminal and waits for it. Returns true on success; failures go to `message`.
    private func run(_ tool: Tool, name: String, headline: String, command: String, directory: URL? = nil,
                     update: @escaping (String) -> Void) async -> Bool {
        running = tool; log = ""; progress = nil; message = nil; cancelRequested = false
        status = String(localized: "Im Terminal-Fenster das Mac-Passwort eingeben …")
        defer { running = nil; job = nil; progress = nil }
        let job = TerminalJob(directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("macOSStudio-Wartung-" + UUID().uuidString), name: name)
        self.job = job
        defer { if job.exitStatus() != nil { job.remove() } }
        do {
            try job.write(rootCommand: command, headline: headline)
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
                message = String(localized: "Terminal wurde nicht gefunden."); return false
            }
            let config = NSWorkspace.OpenConfiguration(); config.activates = true
            _ = try await NSWorkspace.shared.open([job.script], withApplicationAt: terminal, configuration: config)
        } catch {
            message = String(localized: "Terminal konnte nicht geöffnet werden: ") + error.localizedDescription; return false
        }
        let opened = Date()
        var shown = ""
        while true {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let output = job.output()
            if output != shown { shown = output; log = USBProgress.clean(output); update(output) }
            if let code = job.exitStatus() {
                log = USBProgress.clean(job.output()); update(job.output())
                if code == 0 { progress = 1; return true }
                status = ""
                if code == TerminalJob.cancelledExit || cancelRequested { message = String(localized: "Abgebrochen.") }
                else if !TimeMachineBackups.progress(in: log).noAccess {
                    message = String(localized: "Fehlgeschlagen (Code \(code)). Details stehen im Protokoll.")
                }
                return false
            }
            let shell = job.shellRunning()
            if shell == false || (shell == nil && Date().timeIntervalSince(opened) > 120) {
                if job.exitStatus() != nil { continue }
                status = ""
                message = shell == nil ? String(localized: "Terminal hat den Vorgang nicht gestartet. Es wurde nichts geändert.")
                    : String(localized: "Das Terminal-Fenster wurde geschlossen, bevor der Vorgang fertig war.")
                return false
            }
            if cancelRequested, output.isEmpty {
                // Still at the password prompt: nothing has run yet.
                status = ""; message = String(localized: "Abgebrochen. Bitte das Terminal-Fenster schließen – es wurde nichts geändert.")
                return false
            }
        }
    }
}

/// Extras › Mac-Wartung.
struct MaintenanceView: View {
    @ObservedObject var store: MaintenanceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.working || !store.status.isEmpty { statusCard }
            repairCard
            timeMachineCard
        }
        .onAppear { if store.databases.isEmpty && !store.working { store.refreshDatabases() } }
        .alert("Hinweis", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private var statusCard: some View {
        card(store.running == .timeMachine ? String(localized: "Time-Machine-Backups werden gelöscht")
             : store.running == .repair ? String(localized: "Reparatur läuft") : String(localized: "Letzter Vorgang"),
             store.working ? "gearshape.2" : "checkmark.circle") {
            if let progress = store.progress, store.working { ProgressView(value: progress) }
            else if store.working { ProgressView().controlSize(.small) }
            if !store.status.isEmpty { Text(store.status).font(.callout) }
            if !store.log.isEmpty {
                DisclosureGroup("Protokoll") {
                    ScrollView { Text(store.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                }.font(.caption)
            }
            if store.working {
                Button("Abbrechen", role: .destructive) { store.cancel() }
            }
        }
    }

    private var repairCard: some View {
        card(String(localized: "Spotlight & LaunchServices reparieren"), "magnifyingglass") {
            Text("Hilft, wenn Spotlight nichts findet, Programme doppelt oder falsch im „Öffnen mit“-Menü erscheinen, Symbole fehlen oder Dock und Finder hängen.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Label("LaunchServices-Datenbank neu aufbauen", systemImage: "1.circle")
                Label("Spotlight-Index zurücksetzen (wird im Hintergrund neu erstellt)", systemImage: "2.circle")
                Label("Dock, Finder und Menüleiste neu starten", systemImage: "3.circle")
            }.font(.callout)
            HStack {
                Button("Reparatur starten", systemImage: "wrench.and.screwdriver") { store.confirmRepair = true }
                    .buttonStyle(.borderedProminent).disabled(store.working)
                Text("Admin-Passwort nötig. Danach den Mac neu starten.").font(.caption).foregroundStyle(.secondary)
            }
            if store.repairFinished {
                Label("Fertig – bitte den Mac jetzt neu starten.", systemImage: "arrow.clockwise.circle").foregroundStyle(.green)
            }
        }
        .confirmationDialog("Spotlight & LaunchServices reparieren?", isPresented: $store.confirmRepair, titleVisibility: .visible) {
            Button("Reparatur starten") { Task { await store.repair() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dock, Finder und Menüleiste starten kurz neu, Spotlight indexiert danach eine Weile neu. Es werden keine Dateien gelöscht.")
        }
    }

    private var selected: TimeMachineBackups.Machine? { store.machines.first { $0.name == store.selectedMachine } }

    private var timeMachineCard: some View {
        card(String(localized: "Alte Time-Machine-Backups löschen"), "clock.arrow.circlepath") {
            Text("Löscht alle Backups eines Rechners von einem Time-Machine-Laufwerk, z. B. von einem alten Mac, und gibt den Platz frei.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Für Time-Machine-Laufwerke im Format Mac OS Extended (Ordner „Backups.backupdb“). APFS-Backups verwaltet macOS selbst.")
                .font(.caption).foregroundStyle(.secondary)
            if store.databases.isEmpty {
                HStack {
                    Label("Kein solches Time-Machine-Laufwerk angeschlossen.", systemImage: "externaldrive.badge.questionmark").foregroundStyle(.secondary)
                    Spacer()
                    Button("Erneut suchen", systemImage: "arrow.clockwise") { store.refreshDatabases() }.disabled(store.working)
                }
            } else {
                HStack {
                    Picker("Laufwerk", selection: Binding(get: { store.selectedDatabase }, set: { store.selectedDatabase = $0; store.loadMachines() })) {
                        ForEach(store.databases, id: \.self) { Text(store.volumeName($0)).tag(Optional($0)) }
                    }.disabled(store.working)
                    Button { store.refreshDatabases() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Laufwerke neu suchen").disabled(store.working)
                }
                if store.listing { ProgressView().controlSize(.small) }
                if store.accessDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("macOS schützt Time-Machine-Backups. OS Studio braucht dafür „Festplattenvollzugriff“, um die Rechner aufzulisten.", systemImage: "lock.shield")
                            .foregroundStyle(.orange)
                        Text("Unter Systemeinstellungen › Datenschutz & Sicherheit › Festplattenvollzugriff OS Studio einschalten, dann hier erneut laden. Nach einem App-Update kann macOS die Freigabe erneut verlangen. Zum Löschen braucht auch Terminal diesen Zugriff.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Einstellungen öffnen") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                            }
                            Button("Erneut laden") { store.loadMachines() }
                        }
                    }
                }
                if let error = store.listError { Text(error).font(.callout).foregroundStyle(.secondary) }
                if !store.machines.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(store.machines) { machine in
                            Button { store.selectedMachine = machine.name } label: {
                                HStack {
                                    Image(systemName: store.selectedMachine == machine.name ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(store.selectedMachine == machine.name ? Color.accentColor : .secondary)
                                    Image(systemName: "desktopcomputer")
                                    Text(machine.name).fontWeight(.medium)
                                    Spacer()
                                    Text(machine.backups == 1 ? String(localized: "1 Backup") : String(localized: "\(machine.backups) Backups"))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10).contentShape(Rectangle())
                                .background(store.selectedMachine == machine.name ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(store.working)
                        }
                    }
                    HStack {
                        Button("Ausgewählten Rechner löschen …", systemImage: "trash", role: .destructive) { store.confirmDelete = true }
                            .disabled(selected == nil || store.working)
                        Text("Admin-Passwort nötig. Endgültig – nicht rückgängig zu machen.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("Backups endgültig löschen?", isPresented: $store.confirmDelete, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) { Task { await store.deleteSelected() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if let selected, let database = store.selectedDatabase {
                Text("Alle \(selected.backups) Backups von „\(selected.name)“ auf „\(store.volumeName(database))“ werden endgültig gelöscht. Das kann nicht rückgängig gemacht werden und dauert je nach Größe lange.")
            }
        }
    }

    private func card<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title3.bold())
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
