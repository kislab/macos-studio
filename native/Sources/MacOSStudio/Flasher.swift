import AppKit
import SwiftUI
import UniformTypeIdentifiers
import StudioCore

/// iPhone & iPad flasher: restores a connected device (normal, recovery or DFU mode) with a chosen IPSW
/// through Apple Configurator's `cfgutil`. Erases the device; asks before anything is written.
@MainActor final class FlasherStore: ObservableObject {
    @Published var tool: String? = CfgUtil.locate()
    @Published var devices: [FlashDevice] = []
    @Published var scanning = false
    @Published var selected: String?                // ECID
    @Published var ipsw: URL?
    @Published var info: IPSWInfo?
    @Published var reading = false
    @Published var confirm = false
    @Published var confirmCancel = false
    @Published var running = false
    @Published var progress: Double?
    @Published var phase = ""
    @Published var log = ""
    @Published var result: Bool?                    // true = done, false = failed
    @Published var error: String?
    private var command: Command?

    var device: FlashDevice? { devices.first { $0.ecid == selected } }
    var compatible: Bool { guard let device, let info else { return false }; return info.supports(device.productType) }
    var canFlash: Bool { tool != nil && compatible && ipsw != nil && !running }

    func refresh() async {
        tool = CfgUtil.locate()
        guard let tool, !scanning, !running else { return }
        scanning = true; defer { scanning = false }
        let result = try? await Command().run(tool, CfgUtil.listArguments, timeout: 30)
        guard let result, result.status == 0, !result.cancelled, !result.timedOut else { return }
        // cfgutil may print log lines before the JSON object.
        let json = result.output.firstIndex(of: "{").map { String(result.output[$0...]) } ?? result.output
        devices = CfgUtil.devices(fromList: Data(json.utf8))
        if device == nil { selected = devices.count == 1 ? devices[0].ecid : nil }
    }

    func chooseIPSW(startingIn folder: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "ipsw") { panel.allowedContentTypes = [type] }
        panel.directoryURL = folder
        panel.prompt = "Auswählen"
        panel.message = "IPSW-Datei für iPhone oder iPad wählen"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await select(url) }
    }

    func select(_ url: URL) async {
        guard url.pathExtension.lowercased() == "ipsw" else { error = "Bitte eine .ipsw-Datei wählen."; return }
        ipsw = url; info = nil; result = nil; reading = true
        defer { reading = false }
        // Extract only the small plist into a private temp folder (it may be binary, so read it as Data).
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("OSStudio-IPSW-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        for entry in ["Restore.plist", "BuildManifest.plist"] {
            guard let out = try? await Command().run("/usr/bin/unzip", ["-o", "-q", url.path, entry, "-d", temp.path], timeout: 120),
                  out.status == 0, let data = try? Data(contentsOf: temp.appendingPathComponent(entry)) else { continue }
            if let parsed = IPSWInfo.parse(data) { info = parsed; return }
        }
        ipsw = nil
        error = "„\(url.lastPathComponent)“ ist keine lesbare iPhone-/iPad-Firmware (IPSW)."
    }

    func flash(studio: StudioModel) async {
        guard let device, let ipsw, compatible,
              let args = CfgUtil.restoreArguments(ecid: device.ecid, ipsw: ipsw) else { return }
        lastWasRepair = false
        await execute(args, studio: studio, ecid: device.ecid, start: "Wiederherstellung wird gestartet …",
                      done: "Fertig · \(device.modelName) mit \(info?.platform ?? "iOS") \(info?.version ?? "") wiederhergestellt",
                      failure: "Die Wiederherstellung ist fehlgeschlagen.")
    }

    /// Device tab: ECID whose firmware is downloading right now. Downloading never flashes by itself.
    @Published var pendingFlash: String?
    @Published var confirmFlash: (device: FlashDevice, item: Firmware)?

    /// Step 1 in the device tab: only downloads (SHA-1 checked) the firmware for this device.
    func download(for target: FlashDevice, _ item: Firmware, firmware: FirmwareStore, studio: StudioModel) async {
        guard !running, pendingFlash == nil, firmware.existing(item) == nil else { return }
        pendingFlash = target.ecid
        await firmware.start(item, studio: studio)
        pendingFlash = nil
    }

    /// Step 2, only after the user pressed "Flashen" and confirmed: erases the device and installs the
    /// already downloaded IPSW. Stops on any failure without touching the device.
    func flashDownloaded(_ target: FlashDevice, _ item: Firmware, firmware: FirmwareStore, studio: StudioModel) async {
        guard !running, pendingFlash == nil, item.devices.contains(target.productType), let file = firmware.existing(item) else { return }
        selected = target.ecid
        await select(file)
        guard compatible else {
            error = "„\(file.lastPathComponent)“ passt nicht zu \(target.modelName). Es wurde nichts verändert."; return
        }
        guard device != nil else {
            error = "\(target.modelName) ist nicht mehr verbunden. Gerät wieder anstecken (DFU- oder Wiederherstellungsmodus) und erneut „Flashen“ drücken."
            return
        }
        firmware.dismiss()
        await flash(studio: studio)
        lastWasRepair = true            // result belongs to the "Gerät" tab
    }

    /// ECID of the device a cfgutil job is running for (flash, revive or restore).
    @Published var activeECID: String?
    @Published var activeRepair: CfgUtil.Repair?
    @Published var confirmRevive: FlashDevice?
    @Published var confirmRestore: FlashDevice?
    /// The last finished job was a revive/restore (its result belongs to the "Wiederherstellen" tab).
    @Published var lastWasRepair = false

    /// Apple Configurator's "Revive" (keeps data) or "Restore" with the newest signed iOS/iPadOS (erases).
    func repair(_ device: FlashDevice, _ action: CfgUtil.Repair, studio: StudioModel) async {
        guard let args = CfgUtil.repairArguments(ecid: device.ecid, action) else { return }
        activeRepair = action; lastWasRepair = true
        defer { activeRepair = nil }
        switch action {
        case .revive:
            await execute(args, studio: studio, ecid: device.ecid, start: "Reparieren wird gestartet – das System wird neu installiert, Daten bleiben …",
                          done: "Fertig · \(device.modelName) repariert. Das Gerät startet neu.",
                          failure: "Reparieren hat nicht geklappt. Als Nächstes „Wiederherstellen“ versuchen (löscht alle Daten).")
        case .restoreLatest:
            await execute(args, studio: studio, ecid: device.ecid, start: "Neueste Software wird von Apple geladen und installiert …",
                          done: "Fertig · \(device.modelName) mit der neuesten Software wiederhergestellt.",
                          failure: "Die Wiederherstellung ist fehlgeschlagen.")
        }
    }

    private func execute(_ args: [String], studio: StudioModel, ecid: String, start: String, done: String, failure: String) async {
        guard let tool, !running, !studio.busy, !studio.loading else { return }
        studio.busy = true; running = true; result = nil; progress = nil; log = ""; activeECID = ecid
        phase = start
        let runner = Command(); command = runner
        defer { studio.busy = false; running = false; command = nil; activeECID = nil; DockProgress.clear() }
        do {
            let out = try await runner.run(tool, args, timeout: 3 * 3600) { [weak self] chunk in
                Task { @MainActor in self?.report(chunk) }
            }
            if out.cancelled { phase = "Abgebrochen – das Gerät startet ggf. im Wiederherstellungsmodus."; result = false; return }
            if out.timedOut { phase = "Zeitüberschreitung"; result = false; error = "Der Vorgang hat zu lange gedauert."; return }
            if out.status == 0 {
                progress = 100; result = true; phase = done
            } else {
                result = false; phase = "Fehlgeschlagen (Code \(out.status))"
                error = failure + "\n\n" + (CfgUtil.lastLine(in: out.output) ?? "Keine Details von cfgutil.")
            }
        } catch {
            result = false; phase = "Fehlgeschlagen"; self.error = error.localizedDescription
        }
        await refresh()
    }

    func cancel() { command?.cancel() }


    private func report(_ chunk: String) {
        guard running else { return }
        log += chunk
        if log.count > 200_000 { log = String(log.suffix(100_000)) }
        if let value = CfgUtil.percent(in: chunk) { progress = value; DockProgress.show(value / 100) }
        if let line = CfgUtil.lastLine(in: chunk) { phase = line }
    }
}

struct FlasherView: View {
    @ObservedObject var store: FlasherStore
    @ObservedObject var firmware: FirmwareStore
    @ObservedObject var studio: StudioModel
    @ObservedObject var monitor = DeviceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Alle Daten auf dem Gerät werden gelöscht. Vorher ein Backup anlegen. Apple muss die gewählte Version noch signieren – sonst lehnt das Gerät sie ab.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            if store.tool == nil { configuratorMissing } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AutoRecoveryPanel(monitor: monitor, disabled: store.running)
                        deviceCard
                        ipswCard
                        if store.running || store.result != nil { progressCard }
                        HStack {
                            Spacer()
                            Button("Flashen …", systemImage: "bolt.fill") { store.confirm = true }
                                .buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(!store.canFlash || studio.busy || studio.loading)
                        }
                    }
                }
            }
        }
        .onChange(of: monitor.auto) { state in if case .done = state { Task { try? await Task.sleep(nanoseconds: 4_000_000_000); await store.refresh() } } }
        .task {
            monitor.start()
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !store.running { await store.refresh() }
            }
        }
        .confirmationDialog("Gerät wirklich flashen?", isPresented: $store.confirm, titleVisibility: .visible) {
            Button("Löschen und \(store.info?.platform ?? "iOS") \(store.info?.version ?? "") installieren", role: .destructive) {
                Task { await store.flash(studio: studio) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\(store.device?.modelName ?? "Gerät") (ECID \(store.device?.ecid ?? "–")) wird vollständig gelöscht und mit „\(store.ipsw?.lastPathComponent ?? "")“ neu installiert. Das Kabel während des Vorgangs nicht trennen.")
        }
        .confirmationDialog("Vorgang abbrechen?", isPresented: $store.confirmCancel, titleVisibility: .visible) {
            Button("Abbrechen erzwingen", role: .destructive) { store.cancel() }
            Button("Weiter flashen", role: .cancel) {}
        } message: { Text("Ein Abbruch kann das Gerät im Wiederherstellungsmodus zurücklassen. Danach erneut flashen.") }
        .alert("Hinweis", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private var configuratorMissing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Configurator wird benötigt", systemImage: "puzzlepiece.extension").font(.headline)
            Text("Der Flasher nutzt Apples kostenloses „Apple Configurator“ (Werkzeug cfgutil), um IPSW-Dateien auf iPhone und iPad zu installieren.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Im App Store öffnen") { NSWorkspace.shared.open(CfgUtil.appStore) }.buttonStyle(.borderedProminent)
                Button("Erneut prüfen") { Task { await store.refresh() } }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("1. Gerät").font(.headline)
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Geräte neu suchen").disabled(store.running)
            }
            if store.devices.isEmpty {
                Text("Kein Gerät gefunden. iPhone oder iPad per USB verbinden – im normalen Modus (entsperrt, „Vertrauen“ bestätigt), im Wiederherstellungs- oder im DFU-Modus.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Picker("Gerät", selection: $store.selected) {
                    Text("Bitte wählen").tag(String?.none)
                    ForEach(store.devices) { device in
                        Text([device.name.isEmpty ? nil : device.name, device.modelName, device.productType.isEmpty ? nil : device.productType, "ECID \(device.ecid)"]
                            .compactMap { $0 }.joined(separator: " · ")).tag(String?.some(device.ecid))
                    }
                }.labelsHidden().disabled(store.running)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var matchingDownloads: [Firmware] {
        guard let type = store.device?.productType, !type.isEmpty else { return [] }
        return firmware.items.filter { $0.devices.contains(type) && firmware.existing($0) != nil }
    }

    private var ipswCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("2. Firmware (IPSW)").font(.headline)
                Spacer()
                Button("IPSW wählen …", systemImage: "doc.badge.plus") { store.chooseIPSW(startingIn: firmware.folder) }
                    .disabled(store.running)
            }
            ForEach(matchingDownloads) { item in
                if let file = firmware.existing(item), store.ipsw != file {
                    Button("Geladene Firmware verwenden: \(item.platform) \(item.version) (\(item.build))", systemImage: "arrow.down.doc") {
                        Task { await store.select(file) }
                    }.disabled(store.running)
                }
            }
            if store.reading {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("IPSW wird gelesen …").font(.callout) }
            } else if let url = store.ipsw, let info = store.info {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(info.platform) \(info.version) · Build \(info.build) · \(info.productTypes.count) Modell(e)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let device = store.device {
                        if store.compatible {
                            Label("Passt zu \(device.modelName)", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                        } else if device.productType.isEmpty {
                            Label("Gerätemodell unbekannt – Gerät neu verbinden.", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label("Passt nicht zu \(device.modelName) (\(device.productType))", systemImage: "xmark.octagon.fill").font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            } else {
                Text("Eine IPSW-Datei wählen oder unter „Firmware laden“ zuerst herunterladen.").font(.callout).foregroundStyle(.secondary)
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private var progressCard: some View { FlashProgressCard(store: store, title: "3. Flashen") }
}

/// Progress of a running cfgutil job (flash, revive, restore), with cancel and close.
struct FlashProgressCard: View {
    @ObservedObject var store: FlasherStore
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if store.running {
                    Button("Abbrechen", role: .cancel) { store.confirmCancel = true }
                } else {
                    Button("Schließen") { store.result = nil; store.phase = ""; store.progress = nil }
                }
            }
            if store.running {
                if let value = store.progress { ProgressView(value: value, total: 100) } else { ProgressView().progressViewStyle(.linear) }
            }
            HStack {
                if store.result == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                if store.result == false { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                Text(store.phase).lineLimit(2)
                Spacer()
                if let value = store.progress, store.running { Text(String(format: "%.0f %%", value)) }
            }.font(.caption).foregroundStyle(.secondary)
            if store.running { Text("Kabel nicht trennen und den Mac nicht in den Ruhezustand versetzen.").font(.caption).foregroundStyle(.orange) }
        }.padding(16).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
