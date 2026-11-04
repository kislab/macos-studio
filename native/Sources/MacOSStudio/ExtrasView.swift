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
    var guideTask: Task<Void, Never>?
}

/// Extras: recovery mode by click and a guided DFU sequence for iPhone and iPad.
struct ExtrasView: View {
    @ObservedObject var monitor: DeviceMonitor
    @ObservedObject var photos: DevicePhotoStore
    @StateObject private var state = ExtrasState()

    private var inRecovery: [DeviceMonitor.USBDevice] { monitor.usbDevices.filter { $0.mode == .recovery } }
    private var inDFU: [DeviceMonitor.USBDevice] { monitor.usbDevices.filter { $0.mode == .dfu } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Extras").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("iPhone oder iPad per Kabel anschließen. Wiederherstellungsmodus per Klick, DFU-Modus mit Anleitung.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    connectedCard
                    restartCard
                    recoveryCard
                    dfuCard
                    macDFUCard
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

    // MARK: Connected devices

    private var connectedCard: some View {
        card("Angeschlossene Geräte", "cable.connector") {
            if !monitor.available {
                Text("Apples Gerätedienst ist auf diesem Mac nicht verfügbar. Wiederherstellungs- und DFU-Modus werden trotzdem über USB erkannt.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if monitor.devices.isEmpty && monitor.usbDevices.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Warte auf iPhone oder iPad … per USB-Kabel anschließen und entsperren.").foregroundStyle(.secondary)
                }
            }
            ForEach(monitor.devices) { device in
                HStack(spacing: 14) {
                    if let photo = photos.image(for: device.productType) {
                        Image(nsImage: photo).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 86, height: 58).padding(4)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: device.productType.hasPrefix("iPad") ? "ipad" : "iphone")
                            .font(.system(size: 30)).frame(width: 86, height: 58).foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name).font(.headline)
                        Text([device.modelName, device.version.isEmpty ? nil : "iOS \(device.version)"].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !device.paired {
                            Label("Gerät entsperren und „Vertrauen“ tippen", systemImage: "lock").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Button("Wiederherstellungsmodus", systemImage: "arrow.uturn.down.circle") { state.confirm = device }
                        .buttonStyle(.borderedProminent).disabled(monitor.working)
                }
            }
        }
    }

    // MARK: Leave recovery / DFU

    /// Highlighted when a device is in recovery or DFU, so a stuck device is easy to get back.
    private var stuck: Bool { !monitor.usbDevices.isEmpty }
    private var restartCard: some View {
        card(stuck ? "Gerät aus dem Modus holen" : "Gerät neu starten", "power") {
            if stuck {
                Label("Ein Gerät ist im " + (inDFU.isEmpty ? "Wiederherstellungsmodus" : "DFU-Modus") + ". So kommt es wieder heraus:", systemImage: "exclamationmark.circle.fill")
                    .font(.headline).foregroundStyle(.orange)
            } else {
                Text("Hängt ein Gerät im Wiederherstellungs- oder DFU-Modus, kommt es hiermit wieder heraus.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !inRecovery.isEmpty {
                HStack {
                    Text("Wiederherstellungsmodus erkannt – ein Klick genügt.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Normal starten", systemImage: "power") { Task { await monitor.exitRecovery() } }
                        .buttonStyle(.borderedProminent).disabled(monitor.working || !monitor.available)
                }
            }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Per Tasten (funktioniert immer, auch im DFU-Modus):").fontWeight(.medium)
                Spacer()
                Picker("", selection: $state.method) {
                    ForEach(DFUGuide.Method.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 320)
            }
            Text(DFUGuide.forceRestart(for: state.method))
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Recovery

    private var recoveryCard: some View {
        card("Wiederherstellungsmodus", "laptopcomputer.and.iphone") {
            Text("Der Wiederherstellungsmodus zeigt auf dem Display Laptop und Kabel. Der Finder kann das Gerät dann aktualisieren oder wiederherstellen.")
                .font(.callout).foregroundStyle(.secondary)
            if inRecovery.isEmpty {
                Text("Kein Gerät im Wiederherstellungsmodus.").font(.callout)
            } else {
                ForEach(inRecovery) { device in
                    HStack {
                        Label("Gerät im Wiederherstellungsmodus" + (device.cpid.map { " · CPID \($0)" } ?? ""), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Normal starten", systemImage: "power") { Task { await monitor.exitRecovery() } }
                            .disabled(monitor.working || !monitor.available)
                    }
                }
            }
        }
    }

    // MARK: DFU

    private var dfuCard: some View {
        card("DFU-Modus (geführt)", "bolt.horizontal.circle") {
            Text("Den DFU-Modus kann nur das Gerät selbst über seine Tasten auslösen – Apple lässt das per Kabel nicht zu. Die App führt dich mit Countdown durch die Tasten und meldet, sobald es geklappt hat. Im DFU-Modus bleibt der Bildschirm schwarz.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Gerät", selection: $state.method) {
                ForEach(DFUGuide.Method.allCases) { Text($0.title).tag($0) }
            }.disabled(state.guiding)
            if !inDFU.isEmpty || state.dfuReached {
                Label("Gerät ist im DFU-Modus" + (inDFU.first?.cpid.map { " · CPID \($0)" } ?? "") + ". Tasten loslassen – der Finder bietet jetzt die Wiederherstellung an.",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.headline)
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
            Text("Apple-Logo erschienen? Zu lange gehalten – einfach neu starten. Laptop und Kabel zu sehen? Dann ist es der Wiederherstellungsmodus.")
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
                monitor.message = "Der DFU-Modus wurde nicht erkannt. Gerät normal starten (bzw. eingeschaltet lassen) und die Anleitung erneut starten – das Timing ist entscheidend."
            }
        }
    }
    private func stopGuide() { state.guideTask?.cancel(); state.guideTask = nil; state.guiding = false }

    // MARK: Mac DFU over USB-C

    private var macDFUCard: some View {
        card("Mac in DFU versetzen (USB-C)", "bolt.horizontal.circle") {
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
