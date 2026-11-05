import AppKit
import SwiftUI
import StudioCore

/// "Wiederherstellen": like Apple Configurator for devices in recovery or DFU mode.
/// "Reparieren" (cfgutil revive) reinstalls the system and keeps data, which is what Apple suggests first.
/// "Wiederherstellen" (cfgutil restore) loads the newest signed iOS/iPadOS from Apple and erases the device.
struct RepairView: View {
    @ObservedObject var store: FlasherStore
    @ObservedObject var studio: StudioModel
    @ObservedObject var photos: DevicePhotoStore
    @ObservedObject var monitor = DeviceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.tool == nil { configuratorMissing } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AutoRecoveryPanel(monitor: monitor, disabled: store.running)
                        devicesCard
                        if store.activeRepair != nil || (store.result != nil && store.lastWasRepair) {
                            FlashProgressCard(store: store, title: "Fortschritt")
                        }
                        notesCard
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
        .confirmationDialog("Gerät reparieren?", isPresented: Binding(get: { store.confirmRevive != nil }, set: { if !$0 { store.confirmRevive = nil } }), titleVisibility: .visible) {
            Button("Reparieren") {
                if let device = store.confirmRevive { Task { await store.repair(device, .revive, studio: studio) } }
                store.confirmRevive = nil
            }
            Button("Abbrechen", role: .cancel) { store.confirmRevive = nil }
        } message: {
            Text("\(store.confirmRevive?.modelName ?? "Gerät") bekommt sein System neu installiert. Fotos, Apps und Daten bleiben erhalten. Dauert einige Minuten; Kabel nicht trennen.")
        }
        .confirmationDialog("Gerät wirklich wiederherstellen?", isPresented: Binding(get: { store.confirmRestore != nil }, set: { if !$0 { store.confirmRestore = nil } }), titleVisibility: .visible) {
            Button("Alles löschen und neueste Software installieren", role: .destructive) {
                if let device = store.confirmRestore { Task { await store.repair(device, .restoreLatest, studio: studio) } }
                store.confirmRestore = nil
            }
            Button("Abbrechen", role: .cancel) { store.confirmRestore = nil }
        } message: {
            Text("\(store.confirmRestore?.modelName ?? "Gerät") (ECID \(store.confirmRestore?.ecid ?? "–")) wird vollständig gelöscht. Die App lädt die neueste von Apple freigegebene Version (mehrere GB) und installiert sie. Danach kann das Gerät nach der Apple-ID des Besitzers fragen (Aktivierungssperre).")
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

    private enum Mode { case recovery, dfu, normal }
    private func mode(of device: FlashDevice) -> Mode {
        if let usb = monitor.usbDevices.first(where: { $0.ecid.map { CfgUtil.sameECID(cfgutil: device.ecid, usbHex: $0) } ?? false }) {
            return usb.mode == .dfu ? .dfu : usb.mode == .recovery ? .recovery : .normal
        }
        return device.udid == nil ? .recovery : .normal   // cfgutil has no UDID for recovery/DFU devices
    }

    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Geräte", systemImage: "cable.connector").font(.title3.bold())
                Spacer()
                if store.scanning { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Geräte neu suchen").disabled(store.running)
            }
            if store.devices.isEmpty {
                Text("Kein Gerät gefunden. iPhone oder iPad per USB verbinden. Ein Gerät im normalen Modus oben mit „Aktivieren“ in den Wiederherstellungsmodus schicken oder per Tasten (Extras).")
                    .font(.callout).foregroundStyle(.secondary)
                if monitor.usbDevices.contains(where: { $0.mode != .normal }) {
                    Label("Ein Gerät im Wiederherstellungs- oder DFU-Modus ist angeschlossen – es erscheint gleich.", systemImage: "hourglass")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(store.devices) { device in row(device) }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ device: FlashDevice) -> some View {
        let mode = mode(of: device)
        let active = store.activeECID == device.ecid
        let ready = mode != .normal && !store.running && !studio.busy && !studio.loading
        return HStack(spacing: 14) {
            Group {
                if let photo = photos.image(for: device.productType) {
                    Image(nsImage: photo).resizable().interpolation(.high).scaledToFit().padding(4)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: device.productType.hasPrefix("iPad") ? "ipad" : "iphone").font(.system(size: 28)).foregroundStyle(.blue)
                }
            }.frame(width: 72, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(device.name.isEmpty ? device.modelName : device.name).font(.headline)
                    badge(mode)
                    if active { ProgressView().controlSize(.small) }
                }
                Text([device.name.isEmpty ? nil : device.modelName, device.productType.isEmpty ? nil : device.productType, "ECID \(device.ecid)"]
                    .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if mode == .normal {
                    Label("Läuft normal. Zum Reparieren zuerst in den Wiederherstellungsmodus (oben „Aktivieren“).", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button("Reparieren", systemImage: "wrench.and.screwdriver") { store.confirmRevive = device }
                    .buttonStyle(.borderedProminent).disabled(!ready)
                    .help("System neu installieren, Daten bleiben erhalten (Apple: „Revive“)")
                Button("Wiederherstellen …", systemImage: "arrow.counterclockwise") { store.confirmRestore = device }
                    .disabled(!ready)
                    .help("Neueste iOS/iPadOS-Version laden und installieren – löscht alle Daten")
            }
        }
        .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func badge(_ mode: Mode) -> some View {
        let (text, color): (String, Color) = switch mode {
        case .recovery: ("Wiederherstellung", .orange)
        case .dfu: ("DFU", .purple)
        case .normal: ("Normal", .green)
        }
        return Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2).background(color.opacity(0.15), in: Capsule())
    }

    // MARK: Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("So geht man vor (wie Apple Configurator)", systemImage: "list.number").font(.headline)
            Text("1. **Reparieren** zuerst: installiert das System neu, Fotos, Apps und Daten bleiben. Hilft bei Geräten, die im Wiederherstellungsmodus hängen oder nach einem Update nicht mehr starten.")
            Text("2. Klappt das nicht: **Wiederherstellen**. Lädt die neueste von Apple freigegebene iOS-/iPadOS-Version und installiert sie – **alle Daten werden gelöscht**.")
            Text("3. Eine bestimmte Version (IPSW-Datei) installiert der Reiter **Flasher**.")
            Text("Internet ist nötig; der Download ist mehrere GB groß. Mit aktivem „Wo ist?“ fragt das Gerät danach nach der Apple-ID des Besitzers (Aktivierungssperre) – das lässt sich nicht umgehen.")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var configuratorMissing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Apple Configurator wird benötigt", systemImage: "puzzlepiece.extension").font(.headline)
            Text("Reparieren und Wiederherstellen nutzen Apples kostenloses „Apple Configurator“ (Werkzeug cfgutil).")
                .foregroundStyle(.secondary)
            HStack {
                Button("Im App Store öffnen") { NSWorkspace.shared.open(CfgUtil.appStore) }.buttonStyle(.borderedProminent)
                Button("Erneut prüfen") { Task { await store.refresh() } }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
