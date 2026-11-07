import SwiftUI
import StudioCore

@MainActor final class ExtrasState: ObservableObject {
    @Published var confirm: DeviceMonitor.Device?
    @Published var method: DFUGuide.Method = .faceIDiPhone
    @Published var guiding = false
    @Published var stepIndex = 0
    @Published var remaining = 0
    @Published var dfuReached = false
    @Published var confirmMacDFU = false
    @Published var confirmMacReboot = false
    @Published var macTab = false
    @Published var showRestart = false
    var guideTask: Task<Void, Never>?
}

/// Extras: connected devices with their mode, recovery mode by plug-in or click, guided DFU, Mac DFU over USB-C.
struct ExtrasView: View {
    @ObservedObject var monitor: DeviceMonitor
    @ObservedObject var photos: DevicePhotoStore
    /// Jumps to iPhone & iPad → Gerät (flash or repair the device that is now in DFU/recovery).
    var openDevice: () -> Void = {}
    /// Reads cfgutil's device list, so a device in the restore system is not shown as "locked".
    var refreshDevices: () -> Void = {}
    @StateObject private var state = ExtrasState()

    private var inRecovery: [DeviceMonitor.USBDevice] { monitor.usbDevices.filter { $0.mode == .recovery } }
    private var inDFU: [DeviceMonitor.USBDevice] { monitor.usbDevices.filter { $0.mode == .dfu } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Extras").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Geräte in den Wiederherstellungs- oder DFU-Modus bringen – und wieder heraus.")
                    .foregroundStyle(.secondary)
            }
            Picker("Bereich", selection: $state.macTab) {
                Label("iPhone & iPad", systemImage: "iphone").tag(false)
                Label("Mac (USB-C)", systemImage: "laptopcomputer").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.macTab {
                        macDFUCard
                    } else {
                        AutoRecoveryPanel(monitor: monitor, disabled: monitor.working)
                        connectedCard
                        dfuCard
                        restartCard
                    }
                }
            }
        }
        .onAppear {
            monitor.start()
            if let type = monitor.devices.first?.productType, let found = DFUGuide.method(for: type) { state.method = found }
        }
        .onChange(of: monitor.devices) { devices in
            if let type = devices.first?.productType, let found = DFUGuide.method(for: type), !state.guiding { state.method = found }
        }
        .onChange(of: monitor.blockedCount) { count in if count > 0 { refreshDevices() } }
        .onChange(of: inDFU.count) { count in
            if count > 0 && state.guiding { state.dfuReached = true; stopGuide() }
        }
        .confirmationDialog("Wiederherstellungsmodus starten?", isPresented: Binding(get: { state.confirm != nil }, set: { if !$0 { state.confirm = nil } }), titleVisibility: .visible) {
            Button("Wiederherstellungsmodus starten") {
                if let device = state.confirm { Task { await monitor.enterRecovery(device) } }
                state.confirm = nil
            }
            Button("Abbrechen", role: .cancel) { state.confirm = nil }
        } message: {
            Text("„\(state.confirm?.name ?? "")“ startet neu und zeigt Laptop und Kabel. Dabei wird nichts gelöscht – erst eine Wiederherstellung im Finder würde das Gerät löschen. Mit „Normal starten“ kommt es wieder heraus.")
        }
        .alert("Hinweis", isPresented: Binding(get: { monitor.message != nil }, set: { if !$0 { monitor.message = nil } })) {
            Button("OK") { monitor.message = nil }
        } message: { Text(monitor.message ?? "") }
        .onDisappear { stopGuide() }
    }

    // MARK: Connected devices (normal, recovery, DFU in one list)

    private var connectedCard: some View {
        card(String(localized: "Angeschlossene Geräte"), "cable.connector") {
            if !monitor.available {
                Text("Apples Gerätedienst ist auf diesem Mac nicht verfügbar. Wiederherstellungs- und DFU-Modus werden trotzdem über USB erkannt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if monitor.devices.isEmpty && inRecovery.isEmpty && inDFU.isEmpty && monitor.blockedCount == 0 && monitor.restoringCount == 0 {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Kein Gerät angeschlossen – iPhone oder iPad per USB-Kabel verbinden.").foregroundStyle(.secondary)
                }
                Text("Angesteckt, aber nichts erscheint? Ein länger gesperrtes Gerät gibt per USB keine Daten frei. Entsperren – oder per Tasten in den Wiederherstellungsmodus (unten).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if monitor.restoringCount > 0 {
                deviceRow(photo: nil, symbol: "arrow.triangle.2.circlepath", title: String(localized: "Gerät im Restore-System"),
                          detail: String(localized: "Wird gerade wiederhergestellt – oder ist nach einem Abbruch dort hängen geblieben."), badge: ("Restore", .red),
                          note: String(localized: "Hängt es fest: in den DFU-Modus bringen und erneut flashen.")) {
                    Button("Zum Gerät …", systemImage: "bolt.fill") { openDevice() }.buttonStyle(.borderedProminent)
                }
            }
            if monitor.blockedCount > 0 {
                deviceRow(photo: nil, symbol: "lock.iphone", title: String(localized: "iPhone/iPad gesperrt"),
                          detail: String(localized: "Angesteckt, aber das Gerät gibt per USB keine Daten frei."), badge: ("Gesperrt", .orange),
                          note: String(localized: "Entsperren (ggf. „Erlauben“ bzw. „Vertrauen“ tippen) – dann geht es automatisch weiter. Ohne Code: per Tasten.")) {
                    Button("Tasten-Anleitung", systemImage: "hand.point.down") { state.showRestart = true }
                }
            }
            ForEach(monitor.devices) { device in
                deviceRow(photo: photos.image(for: device.productType), symbol: device.productType.hasPrefix("iPad") ? "ipad" : "iphone",
                          title: device.name,
                          detail: [device.modelName, device.version.isEmpty ? nil : "iOS \(device.version)"].compactMap { $0 }.joined(separator: " · "),
                          badge: ("Normal", .green), note: device.paired ? nil : String(localized: "Gesperrt oder nicht vertraut")) {
                    Button("Wiederherstellungsmodus", systemImage: "arrow.uturn.down.circle") { state.confirm = device }
                        .disabled(monitor.working)
                }
            }
            ForEach(inRecovery) { device in
                deviceRow(photo: nil, symbol: "laptopcomputer.and.iphone", title: String(localized: "Gerät im Wiederherstellungsmodus"),
                          detail: device.cpid.map { "CPID \($0)" } ?? "", badge: ("Wiederherstellung", .orange), note: nil) {
                    Button("Flashen …", systemImage: "bolt.fill") { openDevice() }.buttonStyle(.borderedProminent)
                    Button("Normal starten", systemImage: "power") { Task { await monitor.exitRecovery() } }
                        .disabled(monitor.working || !monitor.available)
                }
            }
            ForEach(inDFU) { device in
                deviceRow(photo: nil, symbol: "bolt.horizontal.circle", title: String(localized: "Gerät im DFU-Modus"),
                          detail: device.cpid.map { "CPID \($0)" } ?? "", badge: ("DFU", .purple), note: String(localized: "Zum Verlassen per Tasten neu starten (unten)")) {
                    Button("Flashen …", systemImage: "bolt.fill") { openDevice() }.buttonStyle(.borderedProminent)
                    Button("Verlassen", systemImage: "hand.point.down") { state.showRestart = true }
                }
            }
        }
    }

    private func deviceRow<Actions: View>(photo: NSImage?, symbol: String, title: String, detail: String,
                                          badge: (String, Color), note: String?, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 14) {
            Group {
                if let photo {
                    Image(nsImage: photo).resizable().interpolation(.high).scaledToFit().padding(4)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.blue)
                }
            }.frame(width: 72, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    Text(badge.0).font(.caption2.weight(.semibold)).foregroundStyle(badge.1)
                        .padding(.horizontal, 7).padding(.vertical, 2).background(badge.1.opacity(0.15), in: Capsule())
                }
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                if let note { Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            actions()
        }
        .padding(10).background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Restart by buttons (collapsed)

    private var restartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $state.showRestart) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Funktioniert immer – auch gesperrt, ohne „Vertrauen“ und im DFU-Modus. Gerät: \(state.method.title)").font(.callout).foregroundStyle(.secondary)
                    Text("Normal neu starten").font(.headline)
                    Text(DFUGuide.forceRestart(for: state.method))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    Text("In den Wiederherstellungsmodus").font(.headline)
                    Text(DFUGuide.recoveryButtons(for: state.method))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }.padding(.top, 8)
            } label: {
                Label("Per Tasten: neu starten oder Wiederherstellungsmodus", systemImage: "power").font(.title3.bold())
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: DFU

    private var dfuCard: some View {
        card(String(localized: "DFU-Modus (geführt)"), "bolt.horizontal.circle") {
            Text("DFU geht nur über die Tasten. Die App zählt die Schritte herunter und meldet, sobald es geklappt hat (Bildschirm bleibt schwarz).")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Gerät", selection: $state.method) {
                ForEach(DFUGuide.Method.allCases) { Text($0.title).tag($0) }
            }.disabled(state.guiding)
            if !inDFU.isEmpty || state.dfuReached {
                HStack {
                    Label(String(localized: "Gerät ist im DFU-Modus") + (inDFU.first?.cpid.map { " · CPID \($0)" } ?? "") + ". Tasten loslassen.",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.headline)
                    Spacer()
                    Button("Jetzt flashen …", systemImage: "bolt.fill") { openDevice() }.buttonStyle(.borderedProminent)
                }
            }
            if state.guiding {
                let steps = DFUGuide.steps(for: state.method)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: index < state.stepIndex ? "checkmark.circle.fill" : (index == state.stepIndex ? "hand.point.right.fill" : "circle"))
                                .foregroundStyle(index == state.stepIndex ? .blue : .secondary)
                            Text(step.text).fontWeight(index == state.stepIndex ? .semibold : .regular)
                                .foregroundStyle(index == state.stepIndex ? .primary : .secondary)
                            Spacer()
                            if index == state.stepIndex {
                                Text("\(state.remaining) s").font(.system(.title2, design: .rounded).monospacedDigit().bold()).foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .padding(12).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Button("Abbrechen", role: .cancel) { stopGuide() }
            } else {
                HStack {
                    Button("Anleitung starten", systemImage: "play.fill") { startGuide() }.buttonStyle(.borderedProminent)
                    Text("Gerät vorher per Kabel anschließen.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Apple-Logo? Zu lange gehalten – neu versuchen. Laptop und Kabel? Das ist der Wiederherstellungsmodus.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func startGuide() {
        monitor.start()
        state.dfuReached = false; state.stepIndex = 0; state.guiding = true
        let steps = DFUGuide.steps(for: state.method)
        state.guideTask = Task { @MainActor in
            for (index, step) in steps.enumerated() {
                state.stepIndex = index
                for second in stride(from: step.seconds, to: 0, by: -1) {
                    state.remaining = second
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                }
            }
            // Last step: keep holding until DFU is detected, up to 10 more seconds.
            for second in stride(from: 10, to: 0, by: -1) {
                state.remaining = second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            state.guiding = false
            if inDFU.isEmpty {
                monitor.message = String(localized: "Der DFU-Modus wurde nicht erkannt. Gerät normal starten (bzw. eingeschaltet lassen) und die Anleitung erneut starten – das Timing ist entscheidend.")
            }
        }
    }
    private func stopGuide() { state.guideTask?.cancel(); state.guideTask = nil; state.guiding = false }

    // MARK: Mac DFU over USB-C

    private var macDFUCard: some View {
        card(String(localized: "Mac in DFU versetzen (USB-C)"), "bolt.horizontal.circle") {
            Text("Nur für einen zweiten Mac mit Apple Silicon: über den DFU-Port per USB-C-/Thunderbolt-Kabel verbunden, kann dieser Mac den anderen per Klick in den DFU-Modus versetzen oder neu starten – ohne Tasten. Für iPhone/iPad funktioniert das nicht.")
                .font(.callout).foregroundStyle(.secondary)
            Label("Experimentell und nicht getestet. Admin-Passwort nötig.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
            if !VDMTool.isAppleSilicon {
                Text("Dieser Mac hat Intel – die Funktion steht nur auf Apple-Silicon-Macs zur Verfügung.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Ziel-Mac in DFU versetzen", systemImage: "bolt.fill") { state.confirmMacDFU = true }
                        .buttonStyle(.borderedProminent).disabled(monitor.working)
                    Button("Ziel-Mac neu starten", systemImage: "power") { state.confirmMacReboot = true }
                        .disabled(monitor.working)
                    if monitor.working { ProgressView().controlSize(.small) }
                }
                Text("DFU-Port: bei MacBooks der Anschluss nahe dem Netzteil/MagSafe, beim Mac mini/Studio der Port nächst der Strombuchse.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("Ziel-Mac in DFU versetzen?", isPresented: $state.confirmMacDFU, titleVisibility: .visible) {
            Button("In DFU versetzen") { Task { await monitor.sendMacVDM(reboot: false) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Der per DFU-Port verbundene zweite Mac wird in den DFU-Modus versetzt. Auf diesem Mac passiert nichts.") }
        .confirmationDialog("Ziel-Mac neu starten?", isPresented: $state.confirmMacReboot, titleVisibility: .visible) {
            Button("Neu starten") { Task { await monitor.sendMacVDM(reboot: true) } }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Der per DFU-Port verbundene zweite Mac startet neu.") }
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
