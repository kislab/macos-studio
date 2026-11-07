import SwiftUI
import StudioCore

enum AppSettings {
    static let showChangelogKey = "showChangelogAfterUpdate"
    static let otherMacsKey = "showCatalogOnlyInstallers"
    static let photosKey = "loadDevicePhotos"
    /// Preferences "Alle Einstellungen zurücksetzen" removes. Update bookkeeping stays.
    static let resettable = ["selectedTargetMac", "macCategoryFilter", "macYearFilter", "firmwareFolder",
                             showChangelogKey, otherMacsKey, photosKey]
}

@MainActor final class SettingsState: ObservableObject {
    @Published var confirmReset = false
    @Published var notice: String?
}

struct SettingsView: View {
    @ObservedObject var updates: AppUpdates
    @ObservedObject var model: StudioModel
    @ObservedObject var firmware: FirmwareStore
    @ObservedObject var photos: DevicePhotoStore
    @StateObject private var state = SettingsState()

    private var showChangelog: Binding<Bool> {
        Binding(get: { UserDefaults.standard.object(forKey: AppSettings.showChangelogKey) as? Bool ?? true },
                set: { UserDefaults.standard.set($0, forKey: AppSettings.showChangelogKey); state.objectWillChange.send() })
    }
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (Build \(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Einstellungen").font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Kleine Dinge nach deinem Geschmack. Alles wird sofort gespeichert.").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Updates", "arrow.triangle.2.circlepath") {
                        Toggle("Automatisch nach Updates suchen", isOn: Binding(get: { updates.automaticChecks }, set: { updates.automaticChecks = $0 }))
                        Toggle("Neuigkeiten nach einem Update anzeigen", isOn: showChangelog)
                        HStack {
                            Text("Installierte Version: \(version)").foregroundStyle(.secondary)
                            Spacer()
                            Button("Jetzt nach Updates suchen") { updates.check() }.disabled(!updates.canCheck || model.busy)
                        }
                    }
                    section("macOS-Installer", "arrow.down.circle") {
                        Toggle("Installer für andere Macs anzeigen", isOn: $model.showOtherMacInstallers)
                        Text("Zeigt auch macOS-Versionen, die dieser Mac selbst nicht installieren kann – z. B. für USB-Sticks anderer Macs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    section(String(localized: "iPhone & iPad"), "iphone") {
                        HStack {
                            Text("Speicherort für Firmware").fontWeight(.medium)
                            Spacer()
                            Text(firmware.usesDownloads ? "Downloads" : firmware.folder.path)
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button("Ändern …") { firmware.chooseFolder() }.disabled(firmware.downloading)
                            if !firmware.usesDownloads { Button("Downloads verwenden") { firmware.resetFolder() }.disabled(firmware.downloading) }
                        }
                        Toggle("Gerätefotos von Apple laden", isOn: $photos.enabled)
                        HStack {
                            Text("Fotos werden beim Start von Apples Support-Seiten geladen und auf diesem Mac zwischengespeichert (\(ByteCountFormatter.string(fromByteCount: photos.cacheBytes, countStyle: .file))).")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Zwischenspeicher leeren") { photos.clearCache(); state.notice = String(localized: "Gerätefotos gelöscht.") + (photos.enabled ? String(localized: " Sie werden neu von Apple geladen.") : "") }
                        }
                    }
                    section("Diagnose & Hilfe", "stethoscope") {
                        HStack {
                            Text("Fehlerbericht mit App-Infos und dem letzten Protokoll als Textdatei sichern.").foregroundStyle(.secondary)
                            Spacer()
                            Button("Diagnose exportieren …") { model.exportDiagnostics() }
                        }
                    }
                    section(String(localized: "Zurücksetzen"), "arrow.counterclockwise") {
                        HStack {
                            Text("Ziel-Mac, Filter, Speicherort und alle Schalter auf Standard setzen.").foregroundStyle(.secondary)
                            Spacer()
                            Button("Alle Einstellungen zurücksetzen", role: .destructive) { state.confirmReset = true }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Alle Einstellungen zurücksetzen?", isPresented: $state.confirmReset, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { reset() }
            Button("Abbrechen", role: .cancel) {}
        } message: { Text("Geladene Installer, Firmware-Dateien und USB-Sticks bleiben unverändert.") }
        .alert("Hinweis", isPresented: Binding(get: { state.notice != nil }, set: { if !$0 { state.notice = nil } })) {
            Button("OK") { state.notice = nil }
        } message: { Text(state.notice ?? "") }
    }

    private func reset() {
        AppSettings.resettable.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        updates.automaticChecks = true
        model.showOtherMacInstallers = true
        model.selectedMac = ""
        firmware.resetFolder()
        if !photos.enabled { photos.enabled = true }
        UserDefaults.standard.removeObject(forKey: "selectedTargetMac")
        state.notice = String(localized: "Alle Einstellungen wurden zurückgesetzt.")
    }

    private func section<Content: View>(_ title: String, _ symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title3.bold())
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
