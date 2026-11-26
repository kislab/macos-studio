import AppKit
import SwiftUI
import UniformTypeIdentifiers
import StudioCore

/// Self-made Chrome extensions bundled with the app: put them into a lasting folder, refresh it after updates,
/// export as ZIP and walk through loading them in Chrome.
@MainActor final class ChromeExtensionStore: ObservableObject {
    let extensions: [ChromeExtension]
    @Published private(set) var targets: [String: URL] = [:]
    @Published var message: String?
    /// Bumped after installing, so the installed-version labels re-read the folders.
    @Published private(set) var revision = 0

    init() {
        let directory = Bundle.module.url(forResource: "ChromeExtensions", withExtension: nil)
        extensions = directory.map(ChromeExtension.all(in:)) ?? []
        for ext in extensions {
            if let path = UserDefaults.standard.string(forKey: Self.key(ext)) { targets[ext.name] = URL(fileURLWithPath: path) }
        }
    }

    private static func key(_ ext: ChromeExtension) -> String { "chromeExtensionFolder." + ext.name }

    static var chromeURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") }

    func defaultTarget(_ ext: ChromeExtension) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chrome-Erweiterungen").appendingPathComponent(ext.name)
    }
    func target(_ ext: ChromeExtension) -> URL { targets[ext.name] ?? defaultTarget(ext) }
    func installedVersion(_ ext: ChromeExtension) -> String? { _ = revision; return ext.installedVersion(at: target(ext)) }

    func install(_ ext: ChromeExtension, to url: URL? = nil) {
        let destination = url ?? target(ext)
        do {
            try ext.install(to: destination)
            targets[ext.name] = destination
            UserDefaults.standard.set(destination.path, forKey: Self.key(ext))
            revision += 1
        } catch {
            message = error.localizedDescription
        }
    }

    func chooseFolder(_ ext: ChromeExtension) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = String(localized: "Hier ablegen")
        panel.message = String(localized: "Ordner für „\(ext.name)“ wählen. Chrome lädt die Erweiterung später von hier – den Ordner danach nicht löschen oder verschieben.")
        panel.directoryURL = target(ext).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // A chosen non-empty folder gets its own subfolder, so nothing else in it is touched.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") }) ?? []
        let destination = contents.isEmpty || ext.installedVersion(at: url) != nil ? url : url.appendingPathComponent(ext.name)
        install(ext, to: destination)
    }

    func reveal(_ ext: ChromeExtension) {
        NSWorkspace.shared.activateFileViewerSelecting([target(ext)])
    }

    func exportZip(_ ext: ChromeExtension) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ext.folder.lastPathComponent + "-" + ext.version + ".zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ext.exportZip(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = String(localized: "Die ZIP-Datei konnte nicht gespeichert werden: ") + error.localizedDescription
        }
    }

    /// Chrome does not accept chrome:// links from other apps, so the address goes to the clipboard and Chrome opens.
    func openChrome() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("chrome://extensions", forType: .string)
        guard let chrome = Self.chromeURL else {
            message = String(localized: "Google Chrome ist auf diesem Mac nicht installiert.")
            return
        }
        NSWorkspace.shared.openApplication(at: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct ChromeExtensionView: View {
    @ObservedObject var store: ChromeExtensionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Eigene Erweiterungen für Google Chrome. OS Studio legt sie in einem festen Ordner ab, aus dem Chrome sie lädt, und aktualisiert ihn nach App-Updates.")
                .font(.callout).foregroundStyle(.secondary)
            if store.extensions.isEmpty {
                Text("Keine Erweiterungen in dieser Version enthalten.").foregroundStyle(.secondary)
            }
            ForEach(store.extensions, id: \.name) { ext in
                extensionCard(ext)
            }
            guide
        }
        .alert("Hinweis", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func extensionCard(_ ext: ChromeExtension) -> some View {
        let installed = store.installedVersion(ext)
        let outdated = ext.isNewer(than: store.target(ext))
        return card(ext.name, "puzzlepiece.extension") {
            if !ext.summary.isEmpty { Text(ext.summary).font(.callout) }
            HStack(spacing: 8) {
                badge(String(localized: "Version \(ext.version)"), .blue)
                if outdated, let installed {
                    badge(String(localized: "Im Ordner: \(installed) – bitte aktualisieren"), .orange)
                } else if installed != nil {
                    badge(String(localized: "Im Ordner bereit"), .green)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(store.target(ext).path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button(installed == nil ? "Ordner anlegen" : outdated ? "Ordner aktualisieren" : "Erneut kopieren",
                       systemImage: installed == nil ? "folder.badge.plus" : "arrow.triangle.2.circlepath") { store.install(ext) }
                    .buttonStyle(.borderedProminent)
                Button("Anderen Ordner …") { store.chooseFolder(ext) }
                if installed != nil { Button("Im Finder zeigen", systemImage: "magnifyingglass") { store.reveal(ext) } }
                Spacer()
                Button("Als ZIP exportieren …", systemImage: "square.and.arrow.up") { store.exportZip(ext) }
                    .help("Speichert die Erweiterung als ZIP, z. B. zum Weitergeben oder für den Chrome Web Store.")
            }
            if outdated {
                Label("Nach dem Aktualisieren in Chrome unter chrome://extensions beim Eintrag auf ↻ (Neu laden) klicken. Gespeicherte Einstellungen bleiben erhalten.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var guide: some View {
        card(String(localized: "So installierst du eine Erweiterung in Chrome"), "list.number") {
            step(1, String(localized: "Bei der gewünschten Erweiterung auf **Ordner anlegen** klicken. Den Ordner danach nicht löschen oder verschieben – Chrome lädt die Erweiterung von dort."))
            step(2, String(localized: "**Chrome öffnen** klicken. Die Adresse `chrome://extensions` ist schon kopiert: in die Adresszeile einfügen (⌘V) und Return drücken."))
            step(3, String(localized: "Oben rechts den **Entwicklermodus** einschalten."))
            step(4, String(localized: "**Entpackte Erweiterung laden** klicken und den Ordner aus Schritt 1 wählen (**Im Finder zeigen** verrät, wo er liegt)."))
            step(5, String(localized: "Über das Puzzle-Symbol rechts neben der Adresszeile die Erweiterung **anheften**. Für jede weitere Erweiterung die Schritte 1 und 4 wiederholen."))
            HStack {
                Button("Chrome öffnen", systemImage: "globe") { store.openChrome() }
                    .disabled(ChromeExtensionStore.chromeURL == nil)
                if ChromeExtensionStore.chromeURL == nil {
                    Text("Google Chrome ist nicht installiert.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("**Updates:** Bringt ein OS-Studio-Update eine neue Version mit, hier **Ordner aktualisieren** klicken und in `chrome://extensions` beim Eintrag auf ↻ klicken. Chrome kann beim Start auf Erweiterungen im Entwicklermodus hinweisen – das ist bei selbst geladenen Erweiterungen normal.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)").font(.caption.bold()).foregroundStyle(.white).frame(width: 20, height: 20).background(Color.blue, in: Circle())
            Text(.init(text)).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3).background(color.opacity(0.15), in: Capsule())
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
