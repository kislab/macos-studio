import Foundation
import StudioCore

func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(b), got \(a)") }
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "Check", code: 1) }
    return value
}

final class CoreTests {
    func testAppleCatalog() throws {
        let catalog: [String: Any] = ["Products": [
            "142-50055": ["Packages": [["URL": "https://swcdn.apple.com/x/MajorOSInfo.pkg", "Size": 5],
                                       ["URL": "https://swcdn.apple.com/x/InstallAssistant.pkg", "Size": 17807147403, "Digest": "33D474B5F2819530C7C730F881CD1089B027B913"]],
                          "Distributions": ["English": "https://swdist.apple.com/x/142-50055.English.dist"]],
            "evil": ["Packages": [["URL": "https://example.com/InstallAssistant.pkg", "Size": 1]],
                     "Distributions": ["English": "https://swdist.apple.com/x.dist"]],
            "update": ["Packages": [["URL": "https://swcdn.apple.com/x/Update.pkg", "Size": 1]],
                       "Distributions": ["English": "https://swdist.apple.com/y.dist"]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: catalog, format: .xml, options: 0)
        let products = AppleCatalog.products(fromCatalog: data)
        XCTAssertEqual(products.map(\.id), ["142-50055"])
        XCTAssertEqual(products[0].bytes, 17807147403)
        let dist = "<title>macOS 27 Golden Gate</title><auxinfo><dict>\n<key>BUILD</key>\n<string>26B123</string>\n<key>VERSION</key>\n<string>27.2</string></dict></auxinfo>"
        let info = try XCTUnwrap(AppleCatalog.describe(distribution: dist))
        XCTAssertEqual(info.title, "macOS 27 Golden Gate"); XCTAssertEqual(info.version, "27.2"); XCTAssertEqual(info.build, "26B123")
        XCTAssertNil(AppleCatalog.describe(distribution: "<key>VERSION</key><string>27; rm</string><key>BUILD</key><string>X</string>"))
        let offered = [Installer(title: "macOS Sequoia", version: "15.7", build: "A", bytes: 1)]
        let fromCatalog = [Installer(title: "macOS Sequoia", version: "15.7", build: "A", bytes: 1, packageURL: products[0].package, offeredForThisMac: false),
                           Installer(title: "macOS 27 Golden Gate", version: "27.2", build: "26B123", bytes: 2, packageURL: products[0].package, offeredForThisMac: false)]
        let merged = AppleCatalog.merge(offered: offered, catalog: fromCatalog)
        XCTAssertEqual(merged.map(\.version), ["27.2", "15.7"])
        XCTAssertFalse(merged[0].offeredForThisMac)
        XCTAssertTrue(merged[1].offeredForThisMac)
        XCTAssertNotNil(merged[1].packageURL)
        // gzip round trip using the system tool
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = folder.appendingPathComponent("c.plist")
        try data.write(to: plain)
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); zip.arguments = ["-k", plain.path]
        try zip.run(); zip.waitUntilExit()
        XCTAssertEqual(try Gzip.decompress(Data(contentsOf: plain.appendingPathExtension("gz"))), data)
    }
    func testCatalogSortAndUnits() {
        let text = "* Title: macOS Sonoma, Version: 14.7, Size: 1024KiB, Build: A\n* Title: macOS Sequoia, Version: 15.7.2, Size: 2048 KiB, Build: B, Deferred: NO"
        let items = Installer.parse(text)
        XCTAssertEqual(items.map(\.version), ["15.7.2", "14.7"])
        XCTAssertEqual(items[0].bytes, 2097152)
        XCTAssertTrue(Installer.parse("No installers").isEmpty)
    }
    func testVersionValidation() {
        XCTAssertTrue(Installer.validVersion("15.7.2"))
        XCTAssertFalse(Installer.validVersion("15; touch /tmp/bad"))
        XCTAssertFalse(Installer.validVersion(""))
        XCTAssertTrue(MacModel.isSerialQuery("C02ABC123XYZ"))
        XCTAssertFalse(MacModel.isSerialQuery("A2337"))
        XCTAssertFalse(MacModel.isSerialQuery("MacBookAir10,1"))
        let data = Data(#"{"name":"MacBook Air","category":"MacBook Air","year":2020,"identifiers":["MacBookAir10,1"],"model_numbers":["A2337"],"cpu":"M1","hw_icon":"test","arch":"arm64","min_macos":"11","max_macos":"26","supported_versions":[],"notes":""}"#.utf8)
        let mac = try! JSONDecoder().decode(MacModel.self, from: data)
        XCTAssertTrue(mac.matches(query: "a2337"))
        XCTAssertTrue(mac.matches(query: "MacBookAir10,1"))
        XCTAssertFalse(mac.matches(query: "A2338"))
    }
    func testProgressAndMetrics() throws {
        var metrics = ProgressMetrics()
        let first = try XCTUnwrap(ProgressSample.parse("Installing: 10.0%\r"))
        let second = try XCTUnwrap(ProgressSample.parse("Installing: 20%"))
        XCTAssertNil(metrics.update(first, total: 10e9, time: 0).mbits)
        let next = metrics.update(second, total: 10e9, time: 10)
        XCTAssertEqual(next.bytes, 2e9)
        XCTAssertEqual(next.mbits, 800)
        let phase = try XCTUnwrap(ProgressSample.parse("Downloading: 30%"))
        XCTAssertNil(metrics.update(phase, total: 10e9, time: 20).mbits)
        metrics.reset()
        XCTAssertNil(metrics.update(second, total: 0, time: 30).bytes)
        XCTAssertNil(ProgressSample.parse("Scanning for installer"))
    }
    func testDiskValidationFailsClosed() throws {
        var info: [String: Any] = ["Internal": false, "MountPoint": "/Volumes/Test", "DeviceIdentifier": "disk4s1", "VolumeUUID": "ABC", "TotalSize": 32e9, "BusProtocol": "USB"]
        let target = try XCTUnwrap(ExternalDisk.validated(info))
        var container: [String: Any] = ["ContainerReference": "disk4", "APFSContainerUUID": "CONTAINER", "Volumes": [["DeviceIdentifier": "disk4s1", "APFSVolumeUUID": "ABC"]], "PhysicalStores": [["DeviceIdentifier": "disk3s2", "DiskUUID": "STORE"]]]
        var store: [String: Any] = ["DeviceIdentifier": "disk3s2", "DiskUUID": "STORE", "Internal": false, "BusProtocol": "USB"]
        let plan = try XCTUnwrap(USBPreparation(target: target, container: container, storeInfo: store))
        let shell = plan.shellCommand(name: "Test", mount: "/Volumes/Test")
        XCTAssertTrue(shell.contains("deleteContainer"))
        XCTAssertFalse(shell.contains("eraseDisk"))
        let syntax = Process()
        syntax.executableURL = URL(fileURLWithPath: "/bin/sh")
        syntax.arguments = ["-n", "-c", shell]
        try syntax.run(); syntax.waitUntilExit()
        XCTAssertEqual(syntax.terminationStatus, 0)
        store["Internal"] = true
        XCTAssertNil(USBPreparation(target: target, container: container, storeInfo: store))
        store["Internal"] = false
        container["Volumes"] = [["DeviceIdentifier": "disk4s1", "APFSVolumeUUID": "ABC"], ["DeviceIdentifier": "disk4s2", "APFSVolumeUUID": "OTHER"]]
        XCTAssertNil(USBPreparation(target: target, container: container, storeInfo: store))
        info["Internal"] = true
        XCTAssertNil(ExternalDisk.validated(info))
        info.removeValue(forKey: "Internal")
        XCTAssertNil(ExternalDisk.validated(info))
        info["Internal"] = false
        info["MountPoint"] = "/"
        XCTAssertNil(ExternalDisk.validated(info))
        info["MountPoint"] = "/Volumes/Test"
        info["BusProtocol"] = "PCI-Express"
        XCTAssertNil(ExternalDisk.validated(info))
    }
    func testLocalInstallerProtection() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("StudioFixture-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Install macOS Test.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        XCTAssertNil(LocalInstaller.inspect(app.path))
        let tool = resources.appendingPathComponent("createinstallmedia")
        try Data("test fixture".utf8).write(to: tool)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let item = try XCTUnwrap(LocalInstaller.inspect(app.path))
        XCTAssertEqual(item.bytes, 12)
        XCTAssertNotNil(item.preparationIssue)
        let support = app.appendingPathComponent("Contents/SharedSupport")
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        XCTAssertNotNil(LocalInstaller.preparationIssue(at: app.path))
        let payload = support.appendingPathComponent("SharedSupport.dmg")
        try Data().write(to: payload)
        XCTAssertNotNil(LocalInstaller.preparationIssue(at: app.path))
        try Data("fixture payload".utf8).write(to: payload)
        XCTAssertNil(LocalInstaller.preparationIssue(at: app.path))
        let target = Installer(title: "macOS Test", version: "15.7.2", build: "24G123")
        XCTAssertFalse(try XCTUnwrap(LocalInstaller.inspect(app.path)).matches(target))
        let metadata: [String: Any] = ["System Image Info": ["version": "15.7.2", "build": "24G123"]]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: support.appendingPathComponent("InstallInfo.plist"))
        let identified = try XCTUnwrap(LocalInstaller.inspect(app.path))
        XCTAssertTrue(identified.matches(target))
        XCTAssertFalse(identified.matches(Installer(title: "macOS Test", version: "15.7.1", build: "24G123")))
        XCTAssertFalse(identified.matches(Installer(title: "macOS Test", version: "15.7.2", build: "24G999")))
        try Data().write(to: payload)
        XCTAssertFalse(try XCTUnwrap(LocalInstaller.inspect(app.path)).matches(target))
        try Data("fixture payload".utf8).write(to: payload)
        XCTAssertEqual(LocalInstaller.discover(roots: [root.path], known: [app.path]).count, 1)
        let alias = root.appendingPathComponent("Alias.app")
        try fm.createSymbolicLink(at: alias, withDestinationURL: app)
        XCTAssertNil(LocalInstaller.inspect(alias.path))
        try Data("changed fixture".utf8).write(to: tool)
        var rejected = false
        do { try item.moveToTrash() } catch { rejected = true }
        XCTAssertTrue(rejected)
        XCTAssertTrue(fm.fileExists(atPath: app.path))
        let current = try XCTUnwrap(LocalInstaller.inspect(app.path))
        let owner = try current.authorizedOwnershipCommand(owner: 501)
        XCTAssertTrue(owner.hasSuffix("/usr/sbin/chown -R -P 501 " + shellQuote(app.path)))
        XCTAssertTrue(owner.hasPrefix("test ! -L " + shellQuote(app.path)))
        try Data("changed again".utf8).write(to: tool)
        var changedRejected = false
        do { _ = try current.authorizedOwnershipCommand(owner: 501) } catch { changedRejected = true }
        XCTAssertTrue(changedRejected)
        let refreshed = try XCTUnwrap(LocalInstaller.inspect(app.path))
        try refreshed.moveToTrash()
        XCTAssertFalse(fm.fileExists(atPath: app.path))
    }
    func testQuoting() {
        XCTAssertEqual(shellQuote("a'b"), "'a'\\''b'")
        XCTAssertEqual(shellQuote("$(touch /tmp/no)"), "'$(touch /tmp/no)'")
        XCTAssertEqual(appleScriptQuote("a\"b\\c"), "\"a\\\"b\\\\c\"")
    }
}

extension CoreTests {
    func testTerminalJob() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("studio-check-" + UUID().uuidString)
        let job = TerminalJob(directory: dir)
        defer { job.remove() }
        let text = job.scriptText(rootCommand: "echo 'it''s' && true", headline: "Test")
        XCTAssertTrue(text.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(text.contains("/usr/bin/sudo /usr/bin/script -q -F " + shellQuote(job.logFile.path) + " /bin/bash -c 'echo '\\''it'\\'''\\''s'\\'' && true'"))
        try job.write(rootCommand: "true", headline: "Test")
        let attrs = try FileManager.default.attributesOfItem(atPath: job.script.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o500)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertNil(job.exitStatus())
        try Data("250\n".utf8).write(to: job.statusFile)
        XCTAssertEqual(job.exitStatus(), 250)
        var failed = false
        do { try job.write(rootCommand: "true", headline: "Test") } catch { failed = true }
        XCTAssertTrue(failed)
    }
    func testUSBRootCommand() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("studio-usb-" + UUID().uuidString)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("ro").path); try? fm.removeItem(at: root) }
        let mount = root.appendingPathComponent("Volume"), readOnly = root.appendingPathComponent("ro")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try fm.createDirectory(at: readOnly, withIntermediateDirectories: true)
        let tool = root.appendingPathComponent("fake-createinstallmedia")
        try Data("#!/bin/bash\necho 'Erasing disk: 0%... 100%'\nsleep 3\necho 'Install media now available'\n".utf8).write(to: tool)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        func run(_ job: TerminalJob, mount: URL, cancelAfter: Double? = nil) async throws -> CommandResult {
            try fm.createDirectory(at: job.directory, withIntermediateDirectories: true)
            let command = job.usbRootCommand(safety: "true", mount: mount.path, setup: nil, tool: tool.path, volume: mount.path)
            if let delay = cancelAfter {
                Task { try? await Task.sleep(nanoseconds: UInt64(delay * 1e9)); job.requestCancel() }
            }
            return try await Command().run("/bin/bash", ["-c", command], timeout: 30)
        }
        let normal = try await run(TerminalJob(directory: root.appendingPathComponent("j1")), mount: mount)
        XCTAssertEqual(normal.status, 0)
        XCTAssertTrue(normal.output.contains("Install media now available"))
        XCTAssertFalse(fm.fileExists(atPath: mount.appendingPathComponent(".macOSStudio-Schreibtest").path))
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        let denied = try await run(TerminalJob(directory: root.appendingPathComponent("j2")), mount: readOnly)
        XCTAssertEqual(denied.status, TerminalJob.noWriteAccessExit)
        XCTAssertFalse(denied.output.contains("Erasing"))
        let early = TerminalJob(directory: root.appendingPathComponent("j3"))
        try fm.createDirectory(at: early.directory, withIntermediateDirectories: true)
        early.requestCancel()
        let before = try await run(early, mount: mount)
        XCTAssertEqual(before.status, TerminalJob.cancelledExit)
        XCTAssertFalse(before.output.contains("Erasing"))
        let during = try await run(TerminalJob(directory: root.appendingPathComponent("j4")), mount: mount, cancelAfter: 1.2)
        XCTAssertEqual(during.status, TerminalJob.cancelledExit)
        XCTAssertTrue(during.output.contains("Erasing"))
        XCTAssertFalse(during.output.contains("Install media now available"))
        XCTAssertEqual(USBProgress.parse(during.output)?.step, "Wird abgebrochen")
    }
    func testUSBProgress() {
        XCTAssertNil(USBProgress.parse("Password:"))
        XCTAssertEqual(USBProgress.parse(USBProgress.checkMarker + "\n"), USBProgress(step: "Ziel-Laufwerk wird geprüft", percent: nil))
        let erase = "\u{04}\u{08}\u{08}" + USBProgress.startMarker + "\r\nReady to start.\r\nErasing disk: 0%... 10%... 30%... "
        XCTAssertEqual(USBProgress.parse(erase), USBProgress(step: "USB-Stick wird gelöscht", percent: 30))
        XCTAssertEqual(USBProgress.parse(erase + "100%\nMaking disk bootable...\n"), USBProgress(step: "USB-Stick wird bootfähig gemacht", percent: nil))
        XCTAssertEqual(USBProgress.parse(erase + "100%\nMaking disk bootable...\nCopying to disk: 0%... 10%... 40%"), USBProgress(step: "Installer wird auf den USB-Stick kopiert", percent: 40))
        XCTAssertEqual(USBProgress.parse("Copying to disk: 100%\nInstall media now available at \"/Volumes/X\""), USBProgress(step: "Fertig – USB-Stick ist bereit", percent: nil))
        XCTAssertEqual(USBProgress.clean("a\u{1B}[2Kb\rc"), "ab\nc")
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock(); private var flag = false
    func set() { lock.lock(); flag = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}
@main struct Checks {
    static func main() async throws {
        let tests = CoreTests()
        tests.testCatalogSortAndUnits()
        try tests.testAppleCatalog()
        tests.testVersionValidation()
        try tests.testProgressAndMetrics()
        try tests.testDiskValidationFailsClosed()
        tests.testQuoting()
        try tests.testLocalInstallerProtection()
        try tests.testTerminalJob()
        tests.testUSBProgress()
        if ProcessInfo.processInfo.environment["STUDIO_LIVE"] == "1" {
            let (data, _) = try await URLSession.shared.data(from: AppleCatalog.url)
            let products = AppleCatalog.products(fromCatalog: try Gzip.decompress(data))
            XCTAssertTrue(products.count > 5)
            let (dist, _) = try await URLSession.shared.data(from: products.last!.distribution)
            let info = try XCTUnwrap(AppleCatalog.describe(distribution: String(decoding: dist, as: UTF8.self)))
            // Small signed Apple package from the same product: exercises download, size and signature check.
            let plist = try PropertyListSerialization.propertyList(from: try Gzip.decompress(data), format: nil) as! [String: Any]
            let product = (plist["Products"] as! [String: Any])[products.last!.id] as! [String: Any]
            let small = (product["Packages"] as! [[String: Any]]).first { ($0["URL"] as! String).hasSuffix("MajorOSInfo.pkg") }!
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pkg")
            defer { try? FileManager.default.removeItem(at: target) }
            let progressSeen = LockedFlag()
            _ = try await PackageDownload().run(URL(string: small["URL"] as! String)!, to: target) { written, _ in if written > 0 { progressSeen.set() } }
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: target.path)[.size] as! NSNumber).intValue, (small["Size"] as! NSNumber).intValue)
            let signature = try await Command().run("/usr/sbin/pkgutil", ["--check-signature", target.path], timeout: 60)
            XCTAssertTrue(signature.output.contains("signed Apple Software"))
            XCTAssertTrue(progressSeen.value)
            print("Live Apple catalog: \(products.count) full installers, e.g. \(info.title) \(info.version) (\(info.build))")
        }
        try await tests.testUSBRootCommand()
        let normal = try await Command().run("/usr/bin/printf", ["Installing: 42.5%%\rInstalling: 100%%"], timeout: 5)
        XCTAssertEqual(normal.status, 0)
        XCTAssertEqual(ProgressSample.parse(normal.output)?.percent, 100)
        let timeout = try await Command().run("/bin/sleep", ["10"], timeout: 0.1)
        XCTAssertTrue(timeout.timedOut)
        let cancelled = Command()
        cancelled.cancel()
        let stopped = try await cancelled.run("/bin/sleep", ["10"], timeout: 30)
        XCTAssertTrue(stopped.cancelled)
        XCTAssertFalse(stopped.timedOut)
        print("13 Swift test groups passed: local installers/trash, catalog, Apple catalog/gzip, versions, metrics, disk protection, quoting, terminal job, USB progress, USB root command, output, timeout, cancellation")
    }
}
