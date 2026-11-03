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
    }

    private var startupCheckStarted = false

    func checkOnLaunch() async {
        guard !startupCheckStarted else { return }
        startupCheckStarted = true
        // The window and busy-state callback must exist before showing update UI.
        while isBusy() {
            do { try await Task.sleep(nanoseconds: 500_000_000) }
            catch { startupCheckStarted = false; return }
        }
        controller.startUpdater()
        // Background launch check only offers newer releases; no up-to-date dialog.
        // Invoke before Sparkle's next scheduled runloop cycle.
        if controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
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
