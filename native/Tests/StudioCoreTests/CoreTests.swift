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
    func testIPSWFlash() throws {
        let restore: [String: Any] = ["ProductVersion": "18.1", "ProductBuildVersion": "22B83",
                                      "SupportedProductTypes": ["iPhone17,1", "iPhone17,2", "Watch7,1"]]
        let data = try PropertyListSerialization.data(fromPropertyList: restore, format: .binary, options: 0)
        let info = try XCTUnwrap(IPSWInfo.parse(data))
        XCTAssertEqual(info.productTypes, ["iPhone17,1", "iPhone17,2"])
        XCTAssertTrue(info.supports("iPhone17,2")); XCTAssertFalse(info.supports("iPhone16,1"))
        XCTAssertEqual(info.platform, "iOS")
        XCTAssertEqual(IPSWInfo(version: "17.0", build: "x", productTypes: ["iPad14,1"]).platform, "iPadOS")
        let mac = try PropertyListSerialization.data(fromPropertyList: ["ProductVersion": "15.0", "SupportedProductTypes": ["Mac14,2"]], format: .xml, options: 0)
        XCTAssertNil(IPSWInfo.parse(mac))
        XCTAssertNil(IPSWInfo.parse(Data("kein plist".utf8)))

        XCTAssertTrue(CfgUtil.validECID("0x1A2B3C4D5E6F")); XCTAssertTrue(CfgUtil.validECID("123456"))
        XCTAssertFalse(CfgUtil.validECID("0x1; rm -rf /")); XCTAssertFalse(CfgUtil.validECID(""))
        let file = URL(fileURLWithPath: "/tmp/a b/iPhone.ipsw")
        XCTAssertEqual(CfgUtil.restoreArguments(ecid: "0xABC", ipsw: file) ?? [], ["-e", "0xABC", "--progress", "restore", "-I", "/tmp/a b/iPhone.ipsw"])
        XCTAssertNil(CfgUtil.restoreArguments(ecid: "bad", ipsw: file))
        XCTAssertNil(CfgUtil.restoreArguments(ecid: "0xABC", ipsw: URL(fileURLWithPath: "/tmp/x.dmg")))

        let list = #"{"Command":"list","Output":{"0x1A":{"ECID":"0x1A","deviceType":"iPhone15,2","name":"Kevins iPhone","UDID":"abc"},"0x2B":{"ECID":"0x2B","deviceType":"iPad8,1","name":""},"bad":{"ECID":"x y"}},"Type":"CommandOutput","Devices":["0x1A","0x2B"]}"#
        let devices = CfgUtil.devices(fromList: Data(list.utf8))
        XCTAssertEqual(devices.map(\.ecid), ["0x2B", "0x1A"])
        XCTAssertEqual(devices[1].modelName, "iPhone 14 Pro"); XCTAssertEqual(devices[1].udid, "abc")
        XCTAssertTrue(CfgUtil.devices(fromList: Data(#"{"Command":"list","Output":{},"Devices":[]}"#.utf8)).isEmpty)
        XCTAssertTrue(CfgUtil.devices(fromList: Data("Fehler".utf8)).isEmpty)

        XCTAssertEqual(CfgUtil.percent(in: "Restoring 12%\nRestoring 47.5 %"), 47.5)
        XCTAssertNil(CfgUtil.percent(in: "Waiting for device")); XCTAssertNil(CfgUtil.percent(in: "250%"))
        XCTAssertEqual(CfgUtil.lastLine(in: "a\r\nVerifying restore\n\n"), "Verifying restore")
        XCTAssertTrue(CfgUtil.locate { $0.hasPrefix("/usr/local") } == "/usr/local/bin/cfgutil")
        XCTAssertNil(CfgUtil.locate { _ in false })
    }
    func testFileVerify() {
        XCTAssertTrue(FileVerify.result(actualSize: 100, expectedSize: 100, actualSHA1: "ab", expectedSHA1: "AB") == .ok)
        XCTAssertTrue(FileVerify.result(actualSize: 90, expectedSize: 100, actualSHA1: nil, expectedSHA1: nil) == .wrongSize(expected: 100, actual: 90))
        XCTAssertTrue(FileVerify.result(actualSize: 100, expectedSize: 100, actualSHA1: "cd", expectedSHA1: "ab") == .wrongChecksum)
        XCTAssertTrue(FileVerify.result(actualSize: nil, expectedSize: 100, actualSHA1: nil, expectedSHA1: nil) == .missing)
        XCTAssertTrue(FileVerify.result(actualSize: 100, expectedSize: 100, actualSHA1: nil, expectedSHA1: "ab") == .noReference)
        XCTAssertTrue(FileVerify.result(actualSize: 100, expectedSize: nil, actualSHA1: nil, expectedSHA1: nil) == .noReference)
        XCTAssertTrue(Disk.hasSpace(forPath: NSTemporaryDirectory(), need: 0))
        XCTAssertFalse(Disk.hasSpace(forPath: NSTemporaryDirectory(), need: Int64.max - 1))
    }
    func testVDM() {
        XCTAssertEqual(VDM.fourCC("VDMs"), 0x56444D73)
        XCTAssertEqual(VDM.fourCC("DBMa"), 0x44424D61)
        XCTAssertEqual(VDM.fourCC("LOCK"), 0x4C4F434B)
        XCTAssertEqual(VDM.fourCC("Gaid"), 0x47616964)
        XCTAssertEqual(VDM.args(for: VDM.dfuWords), [0x33, 0x12, 0x80, 0xAC, 0x05, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x80])
        XCTAssertEqual(VDM.args(for: VDM.rebootWords), [0x33, 0x12, 0x80, 0xAC, 0x05, 0x05, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80])
        XCTAssertEqual(VDM.replyHeader(for: VDM.dfuWords), 0x05AC8052)
        XCTAssertEqual(VDM.key(fromBoardName: Array("J416".utf8)), 0x4A343136)
        XCTAssertEqual(VDM.keyBytes(fromBoardName: Array("J416".utf8)), [0x36, 0x31, 0x34, 0x4A])
    }
    func testDFUGuide() {
        XCTAssertTrue(DFUGuide.method(for: "iPhone17,1") == .faceIDiPhone)
        XCTAssertTrue(DFUGuide.method(for: "iPhone10,1") == .faceIDiPhone)   // iPhone 8 uses the new sequence
        XCTAssertTrue(DFUGuide.method(for: "iPhone12,8") == .faceIDiPhone)   // SE 2
        XCTAssertTrue(DFUGuide.method(for: "iPhone9,3") == .iPhone7)
        XCTAssertTrue(DFUGuide.method(for: "iPhone8,1") == .homeButtoniPhone)
        XCTAssertTrue(DFUGuide.method(for: "iPad16,6") == .faceIDiPad)
        XCTAssertTrue(DFUGuide.method(for: "iPad12,1") == .homeButtoniPad)
        XCTAssertTrue(DFUGuide.method(for: "iPod9,1") == .homeButtoniPhone)
        XCTAssertNil(DFUGuide.method(for: "Watch1,1"))
        XCTAssertTrue(DFUGuide.Method.allCases.allSatisfy { !DFUGuide.steps(for: $0).isEmpty })
        XCTAssertTrue(DFUGuide.usbMode(productID: 0x1227) == .dfu)
        XCTAssertTrue(DFUGuide.usbMode(productID: 0x1281) == .recovery)
        XCTAssertTrue(DFUGuide.usbMode(productID: 0x12a8) == .normal)          // normal iPhone
        XCTAssertTrue(DFUGuide.usbMode(productID: 0x12ab) == .normal)          // normal iPad
        XCTAssertNil(DFUGuide.usbMode(productID: 0x8600))                      // other Apple USB device
        let serial = "CPID:8030 CPRV:11 CPFM:03 SCEP:01 BDID:0C ECID:001A2B3C4D5E6F70 IBFL:3C SRTG:[iBoot-7429.61.2]"
        XCTAssertEqual(DFUGuide.field("CPID", in: serial), "8030")
        XCTAssertEqual(DFUGuide.field("ECID", in: serial), "001A2B3C4D5E6F70")
        XCTAssertEqual(DFUGuide.field("SRTG", in: serial), "iBoot-7429.61.2")
        XCTAssertNil(DFUGuide.field("SRNM", in: serial))
        XCTAssertTrue(DFUGuide.Method.allCases.allSatisfy { DFUGuide.forceRestart(for: $0).count > 20 })
        XCTAssertTrue(DFUGuide.Method.allCases.allSatisfy { DFUGuide.recoveryButtons(for: $0).contains("Laptop und Kabel") })
    }
    func testDevicePhotos() throws {
        let html = #"<h2 class="gb-header">Find the model number</h2><p>Intro</p><h2 class="gb-header">iPad&nbsp;Air 13\#u{2011}inch (M4)</h2> <img class="gb-image" alt="x" src="https://cdsassets.apple.com/live/a/ipad-air-13.png" height="1"/><h2 class="gb-header">Evil</h2> <img class="gb-image" src="https://evil.example.com/x.png"/>"#
        let photos = DevicePhotos.parse(html: html)
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos["ipad air 13-inch (m4)"]?.lastPathComponent, "ipad-air-13.png")
        XCTAssertEqual(DevicePhotos.heading(for: "iPad16,10"), "ipad air 13-inch (m4)")
        XCTAssertEqual(DevicePhotos.heading(for: "iPhone14,6"), "iphone se (3rd generation)")
        XCTAssertEqual(DevicePhotos.heading(for: "iPad8,1"), "ipad pro 11-inch")
        XCTAssertEqual(DevicePhotos.heading(for: "iPad6,7"), "ipad pro (12.9-inch)")
        XCTAssertEqual(DevicePhotos.heading(for: "iPad8,11"), "ipad pro 12.9-inch (4th generation)")
        XCTAssertEqual(DevicePhotos.heading(for: "iPad7,3"), "ipad pro (10.5-inch)")
        XCTAssertEqual(DevicePhotos.heading(for: "iPad13,18"), "ipad (10th generation)")
        XCTAssertEqual(DevicePhotos.heading(for: "iPhone19,4"), "iphone duo")
        XCTAssertNil(DevicePhotos.heading(for: "iPod9,1"))
    }
    func testFirmwareCatalog() throws {
        func restore(_ url: String, _ version: String, _ build: String, _ sha: String? = nil) -> [String: Any] {
            var r: [String: Any] = ["FirmwareURL": url, "ProductVersion": version, "BuildVersion": build]
            if let sha { r["FirmwareSHA1"] = sha }
            return ["Restore": r]
        }
        let newURL = "https://updates.cdn-apple.com/x/iPhone17,1_27.2_24B119_Restore.ipsw"
        let list: [String: Any] = ["MobileDeviceSoftwareVersionsByVersion": [
            "16": ["MobileDeviceSoftwareVersions": [
                "iPhone17,1": ["22A1": restore("https://updates.cdn-apple.com/x/old.ipsw", "18.0", "22A1")]]],
            "17": ["MobileDeviceSoftwareVersions": [
                "iPhone17,1": ["22A3351": restore(newURL, "27.2", "24B119", "9C07287009DE10D7FB47D1F60AA5D3B215CA99FC"), "22B83": ["SameAs": "22A3351"]],
                "iPhone17,2": ["Unknown": ["Universal": restore(newURL, "27.2", "24B119")]],
                "iPad8,1": ["X": restore("http://updates-http.cdn-apple.com/y/iPad_Pro_26.7_Restore.ipsw", "26.7", "23H1")],
                "AppleTV5,3": ["X": restore("https://updates.cdn-apple.com/tv.ipsw", "26.0", "T1")],
                "iPhone99,1": ["X": restore("https://evil-cdn-apple.com/a.ipsw", "27.2", "E1")]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
        let items = FirmwareCatalog.parse(data)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.devices.first, "iPhone17,1")
        let phone = try XCTUnwrap(items.first { $0.version == "27.2" })
        XCTAssertEqual(phone.devices, ["iPhone17,1", "iPhone17,2"])
        XCTAssertEqual(phone.deviceNames, ["iPhone 16 Pro", "iPhone 16 Pro Max"])
        XCTAssertEqual(phone.sha1, "9c07287009de10d7fb47d1f60aa5d3b215ca99fc")
        XCTAssertEqual(phone.platform, "iOS")
        XCTAssertTrue(phone.matches(query: "16 pro max"))
        XCTAssertFalse(phone.matches(query: "iPad"))
        let pad = try XCTUnwrap(items.first { $0.devices == ["iPad8,1"] })
        XCTAssertEqual(pad.url.absoluteString, "https://updates.cdn-apple.com/y/iPad_Pro_26.7_Restore.ipsw")
        XCTAssertEqual(pad.platform, "iPadOS")
        XCTAssertEqual(DeviceNames.name(for: "iPhone12,8"), "iPhone SE (2. Generation)")
        XCTAssertEqual(DeviceNames.name(for: "iPhone19,7"), "iPhone 18 Pro Max")
        XCTAssertEqual(DeviceNames.name(for: "iPad17,3"), "iPad Pro (13\", M5)")
        XCTAssertEqual(DeviceNames.name(for: "iPhone99,9"), "iPhone-Modell iPhone99,9")
        XCTAssertTrue(DeviceNames.order("iPhone9,1", "iPhone17,1"))
        XCTAssertTrue(DeviceNames.newestFirst("iPhone13,2", "iPhone12,1"))
        XCTAssertFalse(DeviceNames.newestFirst("iPhone12,1", "iPhone13,2"))
        XCTAssertTrue(DeviceNames.newestFirst("iPhone1,1", "iPad16,6"))
        XCTAssertTrue(DeviceNames.newestFirst("iPad1,1", "iPod9,1"))
        XCTAssertTrue(DeviceNames.design(of: "iPhone10,4") == .homeButton)
        XCTAssertTrue(DeviceNames.design(of: "iPhone10,3") == .notch)
        XCTAssertTrue(DeviceNames.design(of: "iPhone14,6") == .homeButton)
        XCTAssertTrue(DeviceNames.design(of: "iPhone15,2") == .dynamicIsland)
        XCTAssertTrue(DeviceNames.design(of: "iPhone14,7") == .notch)
        XCTAssertTrue(DeviceNames.design(of: "iPhone19,2") == .dynamicIsland)
        XCTAssertTrue(DeviceNames.design(of: "iPad7,11") == .padHomeButton)
        XCTAssertTrue(DeviceNames.design(of: "iPad13,18") == .padFullScreen)
        XCTAssertTrue(DeviceNames.design(of: "iPad12,1") == .padHomeButton)
        XCTAssertTrue(DeviceNames.design(of: "iPad8,1") == .padFullScreen)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try FirmwareCatalog.sha1(of: file), "a9993e364706816aba3e25717850c26c9cd0d89d")
    }
    func testSerialLookup() throws {
        XCTAssertEqual(SerialLookup.configCode(for: " c02abc12hv2r "), "HV2R")
        XCTAssertEqual(SerialLookup.configCode(for: "W8812345DHJ"), "DHJ")
        XCTAssertNil(SerialLookup.configCode(for: "LWV6G7C61M"))
        XCTAssertTrue(SerialLookup.isRandomized("lwv6g7c61m"))
        XCTAssertNil(SerialLookup.url(for: "A&B"))
        XCTAssertEqual(SerialLookup.modelName(fromResponse: "<root><name>CPU Name</name><configCode>MacBook Air (M1, 2020)</configCode></root>"), "MacBook Air (M1, 2020)")
        XCTAssertNil(SerialLookup.modelName(fromResponse: "<root><error>0009</error></root>"))
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/MacOSStudio/Resources/models.json")
        let models = try JSONDecoder().decode([MacModel].self, from: Data(contentsOf: url))
        func names(_ apple: String) -> [String] { SerialLookup.matches(for: apple, in: models).map(\.name) }
        XCTAssertEqual(names("MacBook Air (M1, 2020)"), ["MacBook Air (13\", 2020, M1)"])
        XCTAssertEqual(names("MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)"), ["MacBook Pro (13\" & 15\", 2017)"])
        XCTAssertEqual(names("iMac (27-inch, Mid 2011)"), ["iMac (21.5\" & 27\", Late 2009 – Mid 2011)"])
        XCTAssertEqual(names("MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)"), ["MacBook Pro (13\", 2020, Intel, 2 & 4 Thunderbolt 3)"])
        XCTAssertEqual(names("Mac mini (Late 2014)"), ["Mac mini (Late 2014)"])
        XCTAssertTrue(names("Apple Watch").isEmpty)
    }
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
        let gz = try Data(contentsOf: plain.appendingPathExtension("gz"))
        XCTAssertEqual(try Gzip.decompress(gz), data)
        // FEXTRA header with XLEN 0x01FE: length must be read as one 16-bit value.
        var extra = [UInt8](gz)
        extra[3] |= 0x04
        extra.insert(contentsOf: [0xFE, 0x01] + [UInt8](repeating: 0x41, count: 0x01FE), at: 10)
        XCTAssertEqual(try Gzip.decompress(Data(extra)), data)
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
        try tests.testSerialLookup()
        try tests.testFirmwareCatalog()
        try tests.testDevicePhotos()
        tests.testDFUGuide()
        tests.testVDM()
        tests.testFileVerify()
        try tests.testIPSWFlash()
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
            let (answer, _) = try await URLSession.shared.data(from: SerialLookup.url(for: "HV2R")!)
            XCTAssertEqual(SerialLookup.modelName(fromResponse: String(decoding: answer, as: UTF8.self)), "MacBook Pro (13-inch, 2017, Four Thunderbolt 3 Ports)")
            let (firmwareData, _) = try await URLSession.shared.data(from: FirmwareCatalog.url)
            let firmware = FirmwareCatalog.parse((try? Gzip.decompress(firmwareData)) ?? firmwareData)
            XCTAssertTrue(firmware.count > 30)
            XCTAssertTrue(firmware.allSatisfy { $0.url.scheme == "https" })
            let unnamed = Set(firmware.flatMap(\.devices).filter { DeviceNames.name(for: $0).contains("-Modell") })
            print("Live firmware list: \(firmware.count) IPSWs, \(firmware.filter { $0.sha1 != nil }.count) with SHA-1, unnamed: \(unnamed.sorted())")
            var headings: [String: URL] = [:]
            for page in DevicePhotos.pages {
                var request = URLRequest(url: page); request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
                let (html, _) = try await URLSession.shared.data(for: request)
                headings.merge(DevicePhotos.parse(html: String(decoding: html, as: UTF8.self))) { a, _ in a }
            }
            let ids = Set(firmware.flatMap(\.devices)).filter { !$0.hasPrefix("iPod") }
            let missing = ids.filter { id in DevicePhotos.heading(for: id).flatMap { headings[$0] } == nil }.sorted()
            print("Live device photos: \(headings.count) Apple photos, \(ids.count - missing.count)/\(ids.count) devices matched, missing: \(missing)")
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
        print("20 Swift test groups passed: local installers/trash, catalog, Apple catalog/gzip, serial lookup, firmware list, device photos, DFU guide, VDM, file verify, IPSW flasher, versions, metrics, disk protection, quoting, terminal job, USB progress, USB root command, output, timeout, cancellation")
    }
}
