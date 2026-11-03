import AppKit
import Combine
import Sparkle

@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var canCheck = false
    var isBusy: () -> Bool = { false }
    private(set) lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)

    override init() {
        super.init()
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.startUpdater()
    }

    func check() { controller.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isBusy() {
            throw NSError(domain: "MacOSStudio.Updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bitte den laufenden Vorgang zuerst abschließen oder abbrechen."])
        }
    }

    func updaterShouldRelaunchApplication(_ updater: SPUUpdater) -> Bool {
        // Never replace/relaunch the app while downloading, flashing or deleting.
        !isBusy()
    }
}
