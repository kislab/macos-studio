import AppKit
import Combine
import Sparkle
import Foundation

@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var canCheck = false
    @Published private(set) var startupPending = false
    @Published private(set) var availableVersion: String?
    var isBusy: () -> Bool = { false }
    private lazy var userDriver: AutoRelaunchUserDriver = {
        let driver = AutoRelaunchUserDriver(hostBundle: .main, delegate: nil)
        driver.isBusy = { [weak self] in self?.isBusy() ?? false }
        return driver
    }()
    private(set) lazy var updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: userDriver, delegate: self)
    private var updaterStarted = false
    private func startUpdater() {
        guard !updaterStarted else { return }
        do { try updater.start(); updaterStarted = true }
        catch { NSLog("Sparkle konnte nicht gestartet werden: %@", error.localizedDescription) }
    }

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        if let build = defaults.string(forKey: "availableUpdateBuild"),
           build.compare(current, options: .numeric) == .orderedDescending {
            availableVersion = defaults.string(forKey: "availableUpdateVersion")
        } else {
            defaults.removeObject(forKey: "availableUpdateBuild")
            defaults.removeObject(forKey: "availableUpdateVersion")
        }
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
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
        startupPending = true
        await resolveCurrentFeed()
        startUpdater()
        // Background launch check only offers newer releases; no up-to-date dialog.
        // Invoke before Sparkle's next scheduled runloop cycle.
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        } else { startupPending = false }
    }

    // A unique query avoids stale GitHub/CDN and URL-loading caches for each check.
    // The feed and archive still require their Ed25519 signatures.
    func feedURLString(for updater: SPUUpdater) -> String? {
        if let resolvedFeed { return resolvedFeed }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              var url = URLComponents(string: feed) else { return nil }
        url.queryItems = (url.queryItems ?? []) + [URLQueryItem(name: "check", value: UUID().uuidString)]
        return url.url?.absoluteString
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        startupPending = false
        resolvedFeed = nil
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        startupPending = false
    }

    private var resolvedFeed: String?
    private var resolving = false

    private func resolveCurrentFeed() async {
        resolvedFeed = nil
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/kislab/macos-studio/commits/main?check=" + UUID().uuidString)!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OS-Studio", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = json["sha"] as? String,
                  sha.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else { return }
            resolvedFeed = "https://raw.githubusercontent.com/kislab/macos-studio/" + sha + "/appcast.xml"
        } catch { /* Use the signed main feed when the API is unavailable. */ }
    }

    func check() {
        guard !resolving else { return }
        resolving = true
        Task {
            await resolveCurrentFeed()
            resolving = false
            startUpdater()
            updater.checkForUpdates()
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        UserDefaults.standard.set(item.versionString, forKey: "availableUpdateBuild")
        UserDefaults.standard.set(item.displayVersionString, forKey: "availableUpdateVersion")
    }

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

/// Standard Sparkle UI, but once an update is downloaded and verified the app
/// installs it and relaunches without a second click — unless a task is running.
@MainActor final class AutoRelaunchUserDriver: SPUStandardUserDriver {
    var isBusy: () -> Bool = { false }
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if isBusy() { super.showReady(toInstallAndRelaunch: reply) } else { reply(.install) }
    }
}
