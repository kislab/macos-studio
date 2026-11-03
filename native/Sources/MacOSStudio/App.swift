import SwiftUI
import AppKit
import StudioCore

@main struct MacOSStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = StudioModel()
    @StateObject private var updates = AppUpdates()
    var body: some Scene {
        WindowGroup("macOS Studio") {
            StudioView(model: model)
                .frame(minWidth: 980, minHeight: 720)
                .task {
                    delegate.model = model
                    updates.isBusy = { model.busy || model.loading || model.scanning || model.localScanning }
                    await updates.checkOnLaunch()
                }
        }
        .defaultSize(width: 1140, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { updates.check() }
                    .disabled(!updates.canCheck || model.busy)
            }
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var model: StudioModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows { window.delegate = self }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.busy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Ein Vorgang läuft noch"
        alert.informativeText = model?.flashing == true ? "Bitte die USB-Erstellung abschließen lassen." : "Bitte den Download zuerst abbrechen."
        alert.runModal()
        return .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        applicationShouldTerminate(NSApp) == .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor final class ViewState: ObservableObject {
    @Published var manual = false
    @Published var version = ""
    @Published var confirmErase = false
    @Published var details = false
    @Published var macCategory = "Alle"
    @Published var macYear = 0
    @Published var trashTarget: LocalInstaller?
    @Published var confirmTrash = false
}

struct StudioView: View {
    @ObservedObject var model: StudioModel
    @StateObject private var ui = ViewState()
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                Label("macOS Studio", systemImage: "square.stack.3d.up.fill")
                    .font(.title3.bold()).padding(.top, 20)
                Text("INSTALLER & BOOT MEDIA").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    navigation("download", "Installer laden", "arrow.down.circle")
                    navigation("local", "Installer lokal", "internaldrive")
                    navigation("compatibility", "Mac prüfen", "laptopcomputer")
                    navigation("usb", "USB erstellen", "externaldrive")
                }
                Spacer()
                Text("Von Apple geladen.\nFür deinen Mac vorbereitet.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(5)
                Button("Programme im Finder", systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }.buttonStyle(.plain).font(.caption)
            }.padding(20)
                .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                if model.section == "download" { downloader }
                else if model.section == "local" { localLibrary }
                else if model.section == "compatibility" { compatibility }
                else { usb }
                if !model.activeTitle.isEmpty { activity }
            }
            .padding(28)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(.blue)
        .task { await model.loadCatalog() }
        .alert("Hinweis", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .sheet(isPresented: $ui.manual) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Version anfordern").font(.title2.bold())
                Text("Die Verfügbarkeit einer manuell eingegebenen Version ist nicht geprüft.").foregroundStyle(.secondary)
                TextField("Zum Beispiel 15.7.2", text: $ui.version).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Abbrechen") { ui.manual = false }
                    Spacer()
                    Button("Laden") {
                        ui.manual = false
                        let item = Installer(title: "macOS", version: ui.version.trimmingCharacters(in: .whitespaces))
                        Task { await model.download(item) }
                    }.buttonStyle(.borderedProminent).disabled(!Installer.validVersion(ui.version.trimmingCharacters(in: .whitespaces)))
                }
            }.padding(28).frame(width: 440)
        }
        .confirmationDialog("Installer in den Papierkorb verschieben?", isPresented: $ui.confirmTrash, titleVisibility: .visible) {
            Button("In den Papierkorb", role: .destructive) {
                if let item = ui.trashTarget { Task { await model.trashLocal(item) } }
                ui.trashTarget = nil
            }
            Button("Abbrechen", role: .cancel) { ui.trashTarget = nil }
        } message: {
            Text("\(ui.trashTarget?.name ?? "")\n\(ui.trashTarget?.path ?? "")\n\nDer Installer kann anschließend über den Papierkorb wiederhergestellt werden. Dein installiertes macOS wird nicht gelöscht.")
        }
        .confirmationDialog("USB-Laufwerk vollständig löschen?", isPresented: $ui.confirmErase, titleVisibility: .visible) {
            Button("Laufwerk löschen und Installer erstellen", role: .destructive) { Task { await model.flash() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Alle Daten auf „\(model.disk?.name ?? "")“ (\(model.disk?.mount ?? ""), \(String(format: "%.1f", (model.disk?.bytes ?? 0) / 1e9)) GB) werden gelöscht. Danach folgt die macOS-Administratorfreigabe.")
        }
    }
    private func navigation(_ id: String, _ title: String, _ symbol: String) -> some View {
        Button { model.section = id } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).padding(11)
                .background(model.section == id ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(model.section == id ? Color.accentColor : .primary)
        }.buttonStyle(.plain)
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }
    private var downloader: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Dein nächstes macOS.", "Offizielle Installer. Klare Fortschritte. Bereit für deinen USB-Stick.")
            HStack {
                TextField("Name, Version oder Build suchen", text: $model.query).textFieldStyle(.roundedBorder)
                Button { Task { await model.loadCatalog() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Apple-Katalog neu laden").disabled(model.loading || model.busy)
                Button("Version eingeben") { ui.manual = true }.disabled(model.loading || model.busy)
            }
            HStack {
                Picker("Ziel-Mac", selection: $model.selectedMac) {
                    Text("Alle angebotenen Installer").tag("")
                    ForEach(model.models) { Text($0.name).tag($0.id) }
                }
                if !model.selectedMac.isEmpty { Button("Zurücksetzen") { model.selectedMac = "" } }
            }
            if model.loading { ProgressView(model.catalogStatus).padding() }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.filteredInstallers) { item in
                        HStack(spacing: 16) {
                            InstallerArtwork(title: item.title)
                                .frame(width: 58, height: 58)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline)
                                Text("\(item.version)  ·  Build \(item.build)").font(.subheadline).foregroundStyle(.secondary)
                                Text(String(format: "%.2f GB", item.bytes / 1e9)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Laden", systemImage: "arrow.down") { Task { await model.download(item) } }
                                .buttonStyle(.borderedProminent).disabled(model.busy || model.loading)
                        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !model.loading && model.filteredInstallers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.largeTitle)
                            Text("Keine passenden Installer").font(.headline)
                            Text("Filter ändern oder den Apple-Katalog erneut laden.").foregroundStyle(.secondary)
                        }.padding(40).frame(maxWidth: .infinity)
                    }
                }
            }
            Text(model.catalogStatus).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var localLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Deine Installer auf dem Mac.", "Vorhandene Installations-Apps öffnen, für USB verwenden oder entfernen.")
            HStack {
                Label("\(model.localItems.count) lokale Installer", systemImage: "internaldrive").font(.headline)
                Spacer()
                Button("Installer auswählen …") { model.chooseInstaller() }.disabled(model.busy || model.localScanning)
                Button("Aktualisieren", systemImage: "arrow.clockwise") { Task { await model.scanLocal() } }
                    .disabled(model.localScanning || model.busy)
            }
            Text("Suche in Programme, deinem Programme-Ordner, Downloads und Schreibtisch. Andere Speicherorte kannst du über „Installer auswählen“ hinzufügen.")
                .font(.caption).foregroundStyle(.secondary)
            if model.localScanning { ProgressView("Installer und Größen werden ermittelt …") }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.localItems) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                InstallerArtwork(title: item.name).frame(width: 58, height: 58)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.headline)
                                    Text(item.bytes.map { String(format: "%.2f GB", Double($0) / 1e9) } ?? "Größe nicht vollständig lesbar").foregroundStyle(.secondary)
                                    if let issue = item.preparationIssue {
                                        Label("Unvollständig · nicht für USB verwendbar", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption).foregroundStyle(.orange).help(issue)
                                    } else {
                                        Text("Installationsdaten vorhanden").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(item.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                            }
                            HStack {
                                Button("Im Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") }
                                Button("Für USB verwenden", systemImage: "externaldrive") {
                                    model.selectedInstaller = item.path; model.section = "usb"
                                }.disabled(model.busy || item.preparationIssue != nil)
                                Spacer()
                                Button("Löschen …", systemImage: "trash", role: .destructive) {
                                    ui.trashTarget = item; ui.confirmTrash = true
                                }.disabled(model.busy || model.localScanning)
                            }
                        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !model.localScanning && model.localItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "internaldrive").font(.system(size: 38)).foregroundStyle(.secondary)
                            Text("Keine lokalen Installer gefunden").font(.headline)
                            Text("Lade einen Installer von Apple oder wähle eine vorhandene Installer-App aus.").foregroundStyle(.secondary)
                            Button("Installer laden") { model.section = "download" }
                        }.padding(40).frame(maxWidth: .infinity)
                    }
                }
            }
            if !model.localNotice.isEmpty { Text(model.localNotice).font(.callout).foregroundStyle(.secondary) }
            Text("Löschen verschiebt nur die ausgewählte Installer-App in den Papierkorb. Während eines laufenden Vorgangs ist Löschen gesperrt.")
                .font(.caption).foregroundStyle(.secondary)
        }.task { await model.scanLocal() }
    }
    private var visibleMacs: [MacModel] {
        model.filteredModels.filter {
            (ui.macCategory == "Alle" || $0.category == ui.macCategory) &&
            (ui.macYear == 0 || $0.year == ui.macYear)
        }.sorted { $0.year > $1.year }
    }
    private var compatibility: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Welchen Mac hast du?", "Mac auswählen und passende macOS-Installer finden.")
            HStack(spacing: 16) {
                Image(systemName: "laptopcomputer.and.arrow.down").font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Du sitzt gerade an diesem Mac?").font(.headline)
                    Text("Wir lesen die Modellkennung automatisch aus.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.detectingMac { ProgressView().controlSize(.small) }
                Button("Meinen Mac erkennen") {
                    ui.macCategory = "Alle"; ui.macYear = 0
                    Task { await model.detectMac() }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.detectingMac)
            }.padding(18).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 10) {
                Text("Oder einen anderen Mac auswählen").font(.headline)
                HStack {
                    TextField("Suchen, z. B. MacBook Pro 2019 oder M1", text: $model.modelQuery).textFieldStyle(.roundedBorder)
                    Picker("Modell", selection: $ui.macCategory) {
                        Text("Alle Modelle").tag("Alle")
                        ForEach(Array(Set(model.models.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                    }.frame(width: 210)
                    Picker("Baujahr", selection: $ui.macYear) {
                        Text("Alle").tag(0)
                        ForEach(Array(Set(model.models.map(\.year))).sorted(by: >), id: \.self) { Text(String($0)).tag($0) }
                    }.frame(width: 135)
                }
                HStack {
                    Text("\(visibleMacs.count) Modelle").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !model.modelQuery.isEmpty || ui.macCategory != "Alle" || ui.macYear != 0 {
                        Button("Filter zurücksetzen") { model.modelQuery = ""; ui.macCategory = "Alle"; ui.macYear = 0 }.font(.caption)
                    }
                }
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(visibleMacs) { mac in
                        MacModelCard(mac: mac, detected: model.detectedMacID == mac.id) {
                            model.selectedMac = mac.id; model.query = ""; model.section = "download"
                        }
                    }
                    if visibleMacs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.largeTitle)
                            Text("Kein passender Mac gefunden").font(.headline)
                            Text("Versuche nur den Modellnamen oder setze die Filter zurück.").foregroundStyle(.secondary)
                        }.padding(32).frame(maxWidth: .infinity)
                    }
                }
            }
            Text("Kompatibilität laut gespeicherter Modelldatenbank · keine Live-Auskunft von Apple")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var usb: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Ein Stick. Ein neuer Start.", "Erstelle ein bootfähiges Installationsmedium mit Apples createinstallmedia.")
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label("1  Installer auswählen", systemImage: "macwindow").font(.headline)
                    Picker("Installer", selection: $model.selectedInstaller) {
                        Text("Bitte auswählen").tag("")
                        ForEach(model.localInstallers, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0) }
                    }
                    Button("Andere Installer-App auswählen …") { model.chooseInstaller() }
                    Text(model.selectedInstaller.isEmpty ? "Lade zuerst einen macOS-Installer herunter." : model.selectedInstaller)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }.padding(12)
            }.disabled(model.busy)
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("2  USB-Ziel auswählen", systemImage: "externaldrive").font(.headline)
                        Spacer()
                        Button("Aktualisieren") { Task { await model.scanDisks() } }.disabled(model.scanning || model.busy)
                    }
                    if model.scanning { ProgressView("USB-Laufwerke suchen …") }
                    Picker("USB-Laufwerk", selection: $model.selectedDisk) {
                        Text("Bitte auswählen").tag("")
                        ForEach(model.disks) { Text("\($0.name) · \(String(format: "%.1f", $0.bytes / 1e9)) GB · \($0.identifier)").tag($0.id) }
                    }.disabled(model.busy)
                    Text("Das ausgewählte Volume wird gelöscht. Interne Laufwerke sind ausgeschlossen.").foregroundStyle(.orange).font(.subheadline)
                }.padding(12)
            }
            Button("USB-Installer erstellen", systemImage: "externaldrive.badge.plus") { ui.confirmErase = true }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!model.canFlash)
            Text("Apple Silicon: Beim Einschalten die Ein-/Aus-Taste gedrückt halten.\nIntel: Beim Einschalten die Wahltaste (⌥) gedrückt halten.")
                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(6)
            Spacer(minLength: 0)
        }.task { await model.scanDisks() }
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(model.activeTitle, systemImage: model.flashing ? "externaldrive" : "arrow.down.circle.fill").font(.headline)
                Spacer()
                if model.busy && !model.flashing { Button("Abbrechen", role: .destructive) { model.cancel() } }
                if let pct = model.progress { Text(String(format: "%.1f %%", pct)).monospacedDigit().foregroundStyle(.blue) }
            }
            if let pct = model.progress { ProgressView(value: pct, total: 100) }
            else if model.busy { ProgressView().progressViewStyle(.linear) }
            HStack {
                Text(model.status).font(.subheadline)
                Spacer()
                if model.total > 0 {
                    Text((model.amount.map { String(format: "≈ %.2f", $0 / 1e9) } ?? "—") + String(format: " / %.2f GB", model.total / 1e9)).monospacedDigit()
                }
            }.font(.caption)
            if !model.flashing && model.total > 0 {
                Text("≈ GB-Schätzung aus Apples Fortschritt; Vorbereitung kann Entpacken enthalten.").font(.caption2).foregroundStyle(.secondary)
            }
            if !model.completedPath.isEmpty {
                HStack {
                    Button("Im Finder zeigen") { NSWorkspace.shared.selectFile(model.completedPath, inFileViewerRootedAtPath: "") }
                    Button("USB erstellen") { model.section = "usb" }
                }
            }
            DisclosureGroup("Protokoll", isExpanded: $ui.details) {
                ScrollView { Text(model.log.isEmpty ? "Noch keine Ausgabe." : model.log).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: 110)
            }.font(.caption)
        }.padding(18).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Original release artwork, packaged with the app for offline use.
struct InstallerArtwork: View {
    let title: String
    private var artwork: NSImage? {
        // Longer names must precede their suffixes (High Sierra/Sierra, Mountain Lion/Lion).
        let releases = [
            ("Golden Gate", "golden_gate"), ("Tahoe", "tahoe"),
            ("Sequoia", "sequoia"), ("Sonoma", "sonoma"),
            ("Ventura", "ventura"), ("Monterey", "monterey"),
            ("Big Sur", "big_sur"), ("Catalina", "catalina"),
            ("Mojave", "mojave"), ("High Sierra", "high_sierra"),
            ("Sierra", "sierra"), ("El Capitan", "el_capitan"),
            ("Yosemite", "yosemite"), ("Mavericks", "mavericks"),
            ("Mountain Lion", "mountain_lion"), ("Lion", "lion")
        ]
        let name = releases.first { title.localizedCaseInsensitiveContains($0.0) }?.1 ?? "macos_generic"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "InstallerIcons") else { return nil }
        return NSImage(contentsOf: url)
    }
    var body: some View {
        Group {
            if let artwork {
                Image(nsImage: artwork).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "macwindow.badge.plus").resizable().scaledToFit().foregroundStyle(.blue).padding(10)
            }
        }.accessibilityLabel("\(title) Installer-Symbol")
    }
}

struct MacModelCard: View {
    let mac: MacModel
    let detected: Bool
    let select: () -> Void
    private var hardwareImage: NSImage? {
        guard let url = Bundle.module.url(forResource: mac.hw_icon, withExtension: nil, subdirectory: "Hardware") else { return nil }
        return NSImage(contentsOf: url)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if let image = hardwareImage {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: mac.category.contains("Book") ? "laptopcomputer" : "desktopcomputer").resizable().scaledToFit().padding(12)
                    }
                }.frame(width: 76, height: 64).accessibilityLabel(mac.category)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(mac.category).font(.title3.bold())
                        Text(String(mac.year)).font(.subheadline.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())
                        if detected { Label("Dieser Mac", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                    }
                    Text(mac.name.replacingOccurrences(of: mac.category + " ", with: "")).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(mac.arch).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEUESTE VERSION IN DER DATENBANK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(mac.supported_versions.first.map { "macOS " + $0 } ?? mac.max_macos).font(.headline).foregroundStyle(.blue)
                }
                Spacer()
                Button("Passende Installer", systemImage: "arrow.right") { select() }.buttonStyle(.bordered)
            }
            DisclosureGroup("Weitere Versionen & Modelldetails") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unterstützt: " + mac.supported_versions.joined(separator: ", "))
                    Text("Prozessor: " + mac.cpu)
                    Text("Modellkennung: " + mac.identifiers.joined(separator: ", ")).textSelection(.enabled)
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(detected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
    }
}
