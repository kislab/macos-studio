import AppKit
import SwiftUI
import StudioCore

/// "Gerät": everything for the iPhone/iPad that is plugged in right now – in normal, recovery or DFU mode.
/// The app recognises the model and shows the newest firmware Apple signs for it. Two explicit steps:
/// "Firmware laden" (download only), then "Flashen …" (button + confirmation). Nothing starts by itself.
/// "Reparieren" (Apple Configurator's Revive) keeps the data.
struct DeviceView: View {
    @ObservedObject var store: FlasherStore
    @ObservedObject var firmware: FirmwareStore
    @ObservedObject var studio: StudioModel
    @ObservedObject var photos: DevicePhotoStore
    @ObservedObject var monitor = DeviceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.tool == nil { configuratorMissing } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        devicesCard
                        if firmware.downloading, store.pendingFlash != nil { downloadCard }
                        if store.running || (store.result != nil && store.lastWasRepair) {
                            FlashProgressCard(store: store, title: String(localized: "Fortschritt"))
                        }
                        AutoRecoveryPanel(monitor: monitor, disabled: store.running || store.pendingFlash != nil)
                        notesCard
                    }
                }
            }
        }
        .onChange(of: monitor.auto) { state in if case .done = state { Task { try? await Task.sleep(nanoseconds: 4_000_000_000); await store.refresh() } } }
        .onChange(of: monitor.usbDevices) { _ in Task { await store.refresh() } }   // plugged in / mode changed → list at once
        .task {
            monitor.start()
            if firmware.items.isEmpty { await firmware.load() }
            await store.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if !store.running { await store.refresh() }
            }
        }
        .confirmationDialog("Gerät löschen und flashen?", isPresented: Binding(get: { store.confirmFlash != nil }, set: { if !$0 { store.confirmFlash = nil } }), titleVisibility: .visible) {
            if let pick = store.confirmFlash {
                Button("Löschen und \(pick.item.platform) \(pick.item.version) installieren", role: .destructive) {
                    store.lastWasRepair = true
                    Task { await store.flashDownloaded(pick.device, pick.item, firmware: firmware, studio: studio) }
                    store.confirmFlash = nil
                }
            }
            Button("Abbrechen", role: .cancel) { store.confirmFlash = nil }
        } message: {
            if let pick = store.confirmFlash {
                Text("\(pick.device.modelName) (ECID \(pick.device.ecid)) wird vollständig gelöscht und mit \(pick.item.platform) \(pick.item.version) (\(pick.item.build)) neu installiert. Kabel nicht trennen.")
            }
        }
        .confirmationDialog("Gerät reparieren?", isPresented: Binding(get: { store.confirmRevive != nil }, set: { if !$0 { store.confirmRevive = nil } }), titleVisibility: .visible) {
            Button("Reparieren") {
                if let device = store.confirmRevive { Task { await store.repair(device, .revive, studio: studio) } }
                store.confirmRevive = nil
            }
            Button("Abbrechen", role: .cancel) { store.confirmRevive = nil }
        } message: {
            Text("\(store.confirmRevive?.modelName ?? "Gerät") bekommt sein System neu installiert. Fotos, Apps und Daten bleiben erhalten. Dauert einige Minuten; Kabel nicht trennen.")
        }
        .confirmationDialog("Vorgang abbrechen?", isPresented: $store.confirmCancel, titleVisibility: .visible) {
            Button("Abbrechen erzwingen", role: .destructive) { store.cancel() }
            Button("Weiter", role: .cancel) {}
        } message: { Text("Ein Abbruch kann das Gerät im Wiederherstellungsmodus zurücklassen. Danach einfach erneut starten.") }
        .alert("Hinweis", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    // MARK: Devices

    private enum Mode { case recovery, dfu, normal, restoring }
    private func usb(for device: FlashDevice) -> DeviceMonitor.USBDevice? {
        monitor.usbDevices.first { $0.locationID != nil && $0.locationID == device.locationID }
            ?? monitor.usbDevices.first { $0.ecid.map { CfgUtil.sameECID(cfgutil: device.ecid, usbHex: $0) } ?? false }
    }
    private func mode(of device: FlashDevice) -> Mode {
        if let usb = usb(for: device) {
            switch usb.mode {
            case .dfu: return .dfu
            case .recovery: return .recovery
            // Normal USB ID but no UDID: the restore system is running (or a failed restore got stuck there).
            case .normal: return device.udid == nil ? .restoring : .normal
            }
        }
        return device.udid == nil ? .recovery : .normal   // cfgutil has no UDID for recovery/DFU devices
    }
    /// Newest firmware Apple signs for this model (the catalog keeps only current versions, newest first).
    private func newest(for device: FlashDevice) -> Firmware? {
        device.productType.isEmpty ? nil : firmware.items.first { $0.devices.contains(device.productType) }
    }
    /// Devices in DFU/recovery on USB that cfgutil has not listed yet.
    private var pendingUSB: Int {
        let waiting = monitor.usbDevices.filter { usb in
            usb.mode != .normal && !store.devices.contains { device in usb.ecid.map { CfgUtil.sameECID(cfgutil: device.ecid, usbHex: $0) } ?? false }
        }
        return waiting.count
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Angeschlossene Geräte", systemImage: "cable.connector").font(.title3.bold())
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Geräte neu suchen").disabled(store.running)
            }
            if store.devices.isEmpty && pendingUSB == 0 {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Warte auf ein iPhone oder iPad – per USB anstecken, gern direkt im DFU- oder Wiederherstellungsmodus.")
                        .foregroundStyle(.secondary)
                }
            }
            if pendingUSB > 0 {
                Label("Gerät im DFU- oder Wiederherstellungsmodus erkannt – Modell wird gelesen …", systemImage: "hourglass")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(store.devices) { device in row(device) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ device: FlashDevice) -> some View {
        let mode = mode(of: device)
        let item = newest(for: device)
        let downloaded = item.flatMap { firmware.existing($0) } != nil
        let idle = !store.running && store.pendingFlash == nil && !firmware.downloading && !studio.busy && !studio.loading
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Group {
                    if let photo = photos.image(for: device.productType) {
                        Image(nsImage: photo).resizable().interpolation(.high).scaledToFit().padding(4)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: device.productType.hasPrefix("iPad") ? "ipad" : "iphone").font(.system(size: 30)).foregroundStyle(.blue)
                    }
                }.frame(width: 84, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(device.name.isEmpty ? device.modelName : device.name).font(.headline)
                        badge(mode)
                        if store.activeECID == device.ecid || store.pendingFlash == device.ecid { ProgressView().controlSize(.small) }
                    }
                    Text([device.name.isEmpty ? nil : device.modelName, device.productType.isEmpty ? nil : device.productType, "ECID \(device.ecid)"]
                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            // Firmware for exactly this model
            HStack(spacing: 10) {
                Image(systemName: "shippingbox").foregroundStyle(.secondary)
                if let item {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Neueste Firmware: \(item.platform) \(item.version) (\(item.build))").font(.callout.weight(.medium))
                        Label(downloaded ? String(localized: "Geladen und bereit – zum Flashen auf „Flashen …“ drücken") : String(localized: "Noch nicht geladen – zuerst „Firmware laden“ drücken"),
                              systemImage: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.caption).foregroundStyle(downloaded ? .green : .secondary)
                        if let file = firmware.existing(item) {
                            IPSWLocation(file: file)
                        } else {
                            Text("Wird gespeichert in: \(firmware.folder.path)").font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                    }
                } else if firmware.loading {
                    ProgressView().controlSize(.small); Text("Apple-Firmwareliste wird geladen …").font(.callout).foregroundStyle(.secondary)
                } else if firmware.items.isEmpty {
                    Text("Apple-Firmwareliste nicht geladen.").font(.callout).foregroundStyle(.secondary)
                    Button("Erneut laden") { Task { await firmware.load() } }
                } else {
                    Text(device.productType.isEmpty ? String(localized: "Modell unbekannt – Gerät kurz ab- und wieder anstecken.") : String(localized: "Keine aktuelle Firmware für \(device.productType) bei Apple gefunden."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                if downloaded {
                    Button("Flashen …", systemImage: "bolt.fill") {
                        if let item { store.confirmFlash = (device, item) }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!idle)
                    .help("Löscht das Gerät und installiert die geladene Firmware – nach Rückfrage")
                } else {
                    Button("Firmware laden", systemImage: "arrow.down.circle") {
                        if let item { Task { await store.download(for: device, item, firmware: firmware, studio: studio) } }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(item == nil || !idle)
                    .help("Lädt nur die Firmware und prüft sie – am Gerät wird nichts verändert")
                }
                Button("Reparieren", systemImage: "wrench.and.screwdriver") { store.confirmRevive = device }
                    .controlSize(.large).disabled(mode == .normal || !idle)
                    .help(mode == .normal ? "Nur im Wiederherstellungs- oder DFU-Modus" : "System neu installieren, Daten bleiben erhalten (Apple: „Revive“)")
                Spacer()
                Button("Andere Version …") {
                    store.selected = device.ecid
                    firmware.section = .flasher
                }
                .buttonStyle(.link).disabled(!idle)
                .help("Eine bestimmte IPSW-Datei im Flasher wählen")
            }
            if usb(for: device)?.viaHub == true {
                Label("Über Hub/Dock angeschlossen. Flashen klappt, kann aber länger dauern: Die App wartet länger auf das Gerät und versucht es bei Verbindungsabbruch automatisch bis zu dreimal. Klappt es dann nicht, direkt am Mac anschließen.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if mode == .restoring && !store.running {
                Label("Steckt im Wiederherstellungs-System fest (z. B. nach einem Abbruch). Gerät in den DFU-Modus bringen (Extras) – am besten direkt am Mac – und erneut flashen.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if mode == .normal {
                Label("Läuft normal: Flashen geht nur, wenn das Gerät entsperrt ist und diesem Mac vertraut. Sonst unten „Aktivieren“ für den Wiederherstellungsmodus.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func badge(_ mode: Mode) -> some View {
        let (text, color): (String, Color) = switch mode {
        case .recovery: (String(localized: "Wiederherstellung"), .orange)
        case .dfu: ("DFU", .purple)
        case .normal: (String(localized: "Normal"), .green)
        case .restoring: (String(localized: "Restore-System"), .red)
        }
        return Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
    }

    // MARK: Download before flashing

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Firmware wird geladen").font(.headline)
                Spacer()
                Button("Abbrechen", role: .cancel) { firmware.cancel() }
            }
            if let value = firmware.progress { ProgressView(value: value, total: 100) } else { ProgressView().progressViewStyle(.linear) }
            HStack {
                Text(firmware.phase).lineLimit(1)
                Spacer()
                if firmware.expected > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(firmware.written), countStyle: .file) + " von "
                         + ByteCountFormatter.string(fromByteCount: Int64(firmware.expected), countStyle: .file))
                }
                if let mbits = firmware.mbits { Text(String(format: "· %.0f Mbit/s", mbits)) }
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Text("Es wird nur geladen und geprüft – am Gerät ändert sich nichts. Danach erscheint „Flashen …“.").font(.caption).foregroundStyle(.secondary)
        }.padding(16).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gut zu wissen", systemImage: "lightbulb").font(.headline)
            Text("• Nichts startet von selbst: erst **Firmware laden**, dann **Flashen …** drücken und bestätigen. Flashen löscht das Gerät und installiert die neueste von Apple freigegebene Version.")
            Text("• **Reparieren** zuerst versuchen, wenn die Daten bleiben sollen – laut Apple der erste Schritt für Geräte, die im Wiederherstellungsmodus hängen.")
            Text("• Der **Wiederherstellungsmodus** endet nach etwa 15 Minuten von selbst. Bei langsamem Internet die Firmware vorher laden oder den **DFU-Modus** nutzen.")
            Text("• War „Wo ist?“ aktiv, fragt das Gerät danach nach der Apple-ID des Besitzers (Aktivierungssperre).")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var configuratorMissing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Configurator wird benötigt", systemImage: "puzzlepiece.extension").font(.headline)
            Text("Flashen und Reparieren nutzen Apples kostenloses „Apple Configurator“ (Werkzeug cfgutil).")
                .foregroundStyle(.secondary)
            HStack {
                Button("Im App Store öffnen") { NSWorkspace.shared.open(CfgUtil.appStore) }.buttonStyle(.borderedProminent)
                Button("Erneut prüfen") { Task { await store.refresh() } }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
