import CryptoKit
import Foundation
import StudioCore

func XCTAssertTrue(_ value: Bool, line: UInt = #line) { precondition(value, "line \(line)") }
func XCTAssertFalse(_ value: Bool, line: UInt = #line) { precondition(!value, "line \(line)") }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(b), got \(a)") }
func XCTAssertThrows(_ body: () throws -> Void) { do { try body(); preconditionFailure("Expected an error") } catch {} }
enum SHA256Hex { static func digest(_ data: Data) -> [UInt8] { Array(CryptoKit.SHA256.hash(data: data)) } }
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
        XCTAssertEqual(CfgUtil.restoreArguments(ecid: "0xABC", ipsw: file) ?? [], ["-e", "0xABC", "--timeout", "180", "--progress", "restore", "-I", "/tmp/a b/iPhone.ipsw"])
        XCTAssertNil(CfgUtil.restoreArguments(ecid: "bad", ipsw: file))
        XCTAssertEqual(CfgUtil.repairArguments(ecid: "0xABC", .revive) ?? [], ["-e", "0xABC", "--timeout", "180", "--progress", "revive"])
        XCTAssertEqual(CfgUtil.repairArguments(ecid: "0xABC", .restoreLatest) ?? [], ["-e", "0xABC", "--timeout", "180", "--progress", "restore"])
        XCTAssertTrue(CfgUtil.isRetryable("Error: lost (AMRestoreErrorDomain 4013)"))
        XCTAssertTrue(CfgUtil.isRetryable("Operation \"restore\" failed on 1 devices."))
        XCTAssertFalse(CfgUtil.isRetryable("restore failed: error 3194"))
        XCTAssertNil(CfgUtil.repairArguments(ecid: "0x1; reboot", .revive))
        XCTAssertTrue(CfgUtil.sameECID(cfgutil: "0x1A2B3C4D5E6F70", usbHex: "001A2B3C4D5E6F70"))
        XCTAssertTrue(CfgUtil.sameECID(cfgutil: "4096", usbHex: "1000"))
        // Real iPad Air (M1) in DFU: cfgutil list vs. iBoot USB serial
        let dfuList = #"{"Command":"list","Output":{"0x1511103C0B401E":{"locationID":1179648,"UDID":null,"ECID":"0x1511103C0B401E","name":null,"deviceType":"iPad13,17"}},"Type":"CommandOutput","Devices":["0x1511103C0B401E"]}"#
        let dfu = CfgUtil.devices(fromList: Data(dfuList.utf8))
        XCTAssertEqual(dfu.first?.productType, "iPad13,17"); XCTAssertNil(dfu.first?.udid)
        XCTAssertEqual(dfu.first?.locationID, 0x00120000)                    // ioreg "iPad@00120000"
        // Failure reports
        XCTAssertEqual(CfgUtil.errorCodes(in: "Error: The device could not be restored (AMRestoreErrorDomain 4013)"), [4013])
        XCTAssertTrue(CfgUtil.errorCodes(in: "restore failed: error 3194").contains(3194))
        let report = CfgUtil.failureReport("Step 5 of 7: Restoring\n 49%\n\"restore\" failed on iPad.\nError: lost (AMRestoreErrorDomain 4013)\nOperation \"restore\" failed on 1 devices.\n", viaHub: true)
        XCTAssertTrue(report.contains("Fehler 4013")); XCTAssertTrue(report.contains("USB-Hub")); XCTAssertTrue(report.contains("failed on iPad"))
        XCTAssertFalse(report.contains("49%"))
        XCTAssertNil(CfgUtil.explain(12345))
        let usbSerial = "SDOM:01 CPID:8103 CPRV:11 CPFM:03 SCEP:01 BDID:12 ECID:001511103C0B401E IBFL:3C SRTG:[iBoot-5540.0.0.400.2]"
        XCTAssertTrue(CfgUtil.sameECID(cfgutil: dfu.first?.ecid ?? "", usbHex: DFUGuide.field("ECID", in: usbSerial) ?? ""))
        XCTAssertTrue(DFUGuide.usbMode(productID: 4647) == .dfu)
        XCTAssertEqual(DFUGuide.ecid(fromUDIDSerial: "00008103-001511103C0B401E"), "001511103C0B401E")   // restore OS / normal
        XCTAssertNil(DFUGuide.ecid(fromUDIDSerial: "0123456789abcdef0123456789abcdef01234567"))         // old 40-hex UDID
        XCTAssertTrue(CfgUtil.sameECID(cfgutil: "0x1511103C0B401E", usbHex: DFUGuide.ecid(fromUDIDSerial: "00008103-001511103C0B401E") ?? ""))
        XCTAssertFalse(CfgUtil.sameECID(cfgutil: "0x1A2B", usbHex: "1A2C"))
        XCTAssertFalse(CfgUtil.sameECID(cfgutil: "bad", usbHex: "1A2B"))
        XCTAssertNil(CfgUtil.restoreArguments(ecid: "0xABC", ipsw: URL(fileURLWithPath: "/tmp/x.dmg")))

        let list = #"{"Command":"list","Output":{"0x1A":{"ECID":"0x1A","deviceType":"iPhone15,2","name":"Kevins iPhone","UDID":"abc"},"0x2B":{"ECID":"0x2B","deviceType":"iPad8,1","name":""},"bad":{"ECID":"x y"}},"Type":"CommandOutput","Devices":["0x1A","0x2B"]}"#
        let devices = CfgUtil.devices(fromList: Data(list.utf8))
        XCTAssertEqual(devices.map(\.ecid), ["0x2B", "0x1A"])
        XCTAssertEqual(devices[1].modelName, "iPhone 14 Pro"); XCTAssertEqual(devices[1].udid, "abc")
        XCTAssertTrue(CfgUtil.devices(fromList: Data(#"{"Command":"list","Output":{},"Devices":[]}"#.utf8)).isEmpty)
        XCTAssertTrue(CfgUtil.devices(fromList: Data("Fehler".utf8)).isEmpty)

        XCTAssertEqual(CfgUtil.percent(in: "Restoring 12%\nRestoring 47.5 %"), 47.5)
        XCTAssertNil(CfgUtil.percent(in: "Waiting for device")); XCTAssertNil(CfgUtil.percent(in: "250%"))
        // Step-wise cfgutil output → steady overall progress
        var steps = CfgUtil.StepProgress()
        XCTAssertNil(steps.overall)
        steps.consume("Step 1 of 4: Preparing\n 50%\n")
        XCTAssertEqual(steps.overall, 12.5); XCTAssertEqual(steps.title, "Preparing")
        steps.consume("Step 2 of 4: Restoring iPad\n 49")         // line split across chunks
        steps.consume("%\n")
        XCTAssertEqual(steps.step, 2); XCTAssertEqual(steps.stepPercent, 49)
        XCTAssertTrue(abs((steps.overall ?? 0) - 37.25) < 0.01)
        steps.consume("Schritt 4 von 4: Abschließen 100%\n")
        XCTAssertEqual(steps.overall, 100); XCTAssertEqual(steps.title, "Abschließen")
        steps.consume("Step 3 of 4: x\n 0%\n")                   // never goes backwards
        XCTAssertEqual(steps.overall, 100)
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
        XCTAssertEqual(DeviceNames.name(for: "iPad19,2"), "iPad mini (A20 Pro)")
        XCTAssertTrue(DeviceNames.design(of: "iPad19,1") == .padFullScreen)
        XCTAssertEqual(DevicePhotos.heading(for: "iPad19,1"), "ipad mini (a20 pro)")
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
        var seen = 0.0
        _ = try FirmwareCatalog.sha1(of: file, progress: { seen = $0 })
        XCTAssertEqual(seen, 1)
        // Checksums cover every listed file, also older versions that parse() hides; none for the untrusted host.
        let sums = FirmwareCatalog.checksums(data)
        XCTAssertEqual(sums["iPhone17,1_27.2_24B119_Restore.ipsw"], "9c07287009de10d7fb47d1f60aa5d3b215ca99fc")
        XCTAssertNil(sums["old.ipsw"])                       // listed without SHA-1
        XCTAssertNil(sums["a.ipsw"])
    }
    func testDeviceDiscovery() throws {
        // Apple's lists: identifiers per device; newest macOS per Mac.
        func restore(_ version: String) -> [String: Any] { ["Restore": ["ProductVersion": version, "BuildVersion": "X1", "FirmwareURL": "https://updates.cdn-apple.com/x.ipsw"]] }
        let feed: [String: Any] = ["MobileDeviceSoftwareVersionsByVersion": [
            "1": ["MobileDeviceSoftwareVersions": ["Mac18,2": ["A": restore("26.4")], "VirtualMac2,1": ["A": restore("27.2")]]],
            "2": ["MobileDeviceSoftwareVersions": ["Mac18,2": ["B": restore("27.2")], "Mac14,2": ["B": restore("27.1")],
                                                   "iPad19,1": ["C": restore("27.2")], "Watch7,1": ["D": restore("13.0")], "iPhone1,1; rm": ["E": restore("1.0")]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: feed, format: .xml, options: 0)
        XCTAssertEqual(DeviceDiscovery.macs(fromRestoreFeed: data), ["Mac18,2": "27.2", "Mac14,2": "27.1"])
        XCTAssertEqual(DeviceDiscovery.mobileIdentifiers(fromDeviceList: data), ["iPad19,1"])
        XCTAssertTrue(DeviceDiscovery.valid("MacBookPro18,3")); XCTAssertTrue(DeviceDiscovery.valid("iMac21,1"))
        XCTAssertFalse(DeviceDiscovery.valid("../x")); XCTAssertFalse(DeviceDiscovery.valid("VirtualMac2,1"))
        XCTAssertTrue(DeviceDiscovery.isMac("Macmini9,1")); XCTAssertFalse(DeviceDiscovery.isMac("iPad19,1"))
        XCTAssertEqual(DeviceDiscovery.appleDBURL(for: "iPad19,1")?.absoluteString, "https://api.appledb.dev/device/iPad19,1.json")
        XCTAssertNil(DeviceDiscovery.appleDBURL(for: "iPad19,1/../../x"))
        // AppleDB records (shape as served by api.appledb.dev)
        let pad = Data(#"{"name":"iPad mini (A20 Pro) Wi-Fi + Cellular","identifier":["iPad19,2"],"soc":"A20 Pro","type":"iPad mini","released":"2026-11-06","model":["A3596","A3597","bad"]}"#.utf8)
        let record = try XCTUnwrap(DeviceDiscovery.record(fromAppleDB: pad, identifier: "iPad19,2"))
        XCTAssertEqual(DeviceDiscovery.displayName(record), "iPad mini (A20 Pro)")
        XCTAssertEqual(record.models, ["A3596", "A3597"])
        XCTAssertNil(DeviceDiscovery.record(fromAppleDB: pad, identifier: "iPad19,1"))          // record for another device
        XCTAssertNil(DeviceDiscovery.record(fromAppleDB: Data("{}".utf8), identifier: "iPad19,2"))
        let imacData = Data(#"{"name":"iMac (24-inch, M6, 2026)","identifier":["Mac18,2"],"soc":"M6","type":"iMac","released":"2026-11-06","model":["A3589","A3590"]}"#.utf8)
        let imac = DeviceDiscovery.macModel(identifier: "Mac18,2", record: try XCTUnwrap(DeviceDiscovery.record(fromAppleDB: imacData, identifier: "Mac18,2")), newestMacOS: "27.2")
        XCTAssertEqual(imac.category, "iMac"); XCTAssertEqual(imac.year, 2026); XCTAssertEqual(imac.hw_icon, "imac_m_series.png")
        XCTAssertEqual(imac.cpu, "Apple M6"); XCTAssertEqual(imac.supported_versions, ["Golden Gate"]); XCTAssertEqual(imac.min_macos, "macOS Golden Gate 27")
        XCTAssertTrue(imac.supports(Installer(title: "macOS 27 Golden Gate", version: "27.2", build: "X")))
        XCTAssertFalse(imac.supports(Installer(title: "macOS Tahoe", version: "26.4", build: "Y")))
        XCTAssertTrue(imac.matches(query: "A3590"))
        let future = DeviceDiscovery.macModel(identifier: "Mac20,1", record: DeviceDiscovery.Record(name: "Mac Pro (2028)", type: "Mac Pro", soc: nil, released: nil, models: []), newestMacOS: "29.0")
        XCTAssertEqual(future.supported_versions, ["macOS 29"]); XCTAssertEqual(future.hw_icon, "mac_pro.png"); XCTAssertEqual(future.cpu, "Apple Silicon")
        // Learned names fill gaps; the built-in table wins.
        XCTAssertEqual(DeviceNames.name(for: "iPhone99,1"), "iPhone-Modell iPhone99,1")
        DeviceNames.learn(["iPhone99,1": "iPhone 30 Pro", "iPhone17,1": "falsch"])
        XCTAssertEqual(DeviceNames.name(for: "iPhone99,1"), "iPhone 30 Pro")
        XCTAssertEqual(DeviceNames.name(for: "iPhone17,1"), "iPhone 16 Pro")
        XCTAssertTrue(DeviceNames.isBuiltIn("iPad19,1")); XCTAssertFalse(DeviceNames.isBuiltIn("iPhone99,1"))
    }
    func testIntegrityAndLegacyInstaller() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Chunk list in Apple's CNKL layout: 36-byte header, then (UInt32 size + SHA-256) per chunk.
        func chunklist(_ pieces: [Data]) -> Data {
            func le<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
            var out: [UInt8] = Array("CNKL".utf8) + le(UInt32(36)) + [1, 1, 2, 0] + le(UInt64(pieces.count)) + le(UInt64(36)) + le(UInt64(36 + 36 * pieces.count))
            for piece in pieces { out += le(UInt32(piece.count)) + Array(SHA256Hex.digest(piece)) }
            return Data(out)
        }
        let a = Data(repeating: 0x41, count: 1000), b = Data("Ende".utf8)
        let file = folder.appendingPathComponent("x.dmg")
        try (a + b).write(to: file)
        let list = try XCTUnwrap(Chunklist.parse(chunklist([a, b])))
        XCTAssertEqual(list.chunks.count, 2); XCTAssertEqual(list.totalBytes, 1004)
        var last = 0.0
        XCTAssertEqual(try list.verify(file, progress: { last = $0 }), .ok)
        XCTAssertEqual(last, 1)
        try (a + Data("ENDE".utf8)).write(to: file)
        XCTAssertEqual(try list.verify(file), .mismatch(chunk: 1))
        try a.write(to: file)
        XCTAssertEqual(try list.verify(file), .wrongSize(expected: 1004, actual: 1000))
        XCTAssertNil(Chunklist.parse(Data("CNKL kaputt".utf8)))
        XCTAssertNil(Chunklist.parse(Data(repeating: 0, count: 64)))
        var truncated = chunklist([a, b]); truncated.removeLast(40)
        XCTAssertNil(Chunklist.parse(truncated))
        try (a + b).write(to: file)
        do { _ = try list.verify(file, isCancelled: { true }); XCTAssertTrue(false) } catch { XCTAssertTrue(error is CancellationError) }

        // Assembling an installer app from the 10.13–10.15 parts.
        XCTAssertEqual(LegacyInstaller.sharedSupportName(for: "InstallESDDmg.pkg"), "InstallESD.dmg")
        XCTAssertEqual(LegacyInstaller.sharedSupportName(for: "BaseSystem.chunklist"), "BaseSystem.chunklist")
        XCTAssertNil(LegacyInstaller.sharedSupportName(for: "InstallAssistantAuto.pkg"))
        let expanded = folder.appendingPathComponent("expanded")
        let app = expanded.appendingPathComponent("Payload/Install macOS Catalina.app")
        let resources = app.appendingPathComponent("Contents/Resources"), support = app.appendingPathComponent("Contents/SharedSupport")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        XCTAssertNil(LegacyInstaller.stubApp(inExpanded: expanded))                 // no createinstallmedia yet
        let tool = resources.appendingPathComponent("createinstallmedia")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        XCTAssertEqual(LegacyInstaller.stubApp(inExpanded: expanded)?.lastPathComponent, "Install macOS Catalina.app")
        let parts = ["InstallESDDmg.pkg", "BaseSystem.dmg", "BaseSystem.chunklist", "InstallAssistantAuto.pkg"]
        var files: [String: URL] = [:]
        for name in parts { let url = folder.appendingPathComponent(name); try Data(name.utf8).write(to: url); files[name] = url }
        // Unknown InstallInfo.plist layout → refused.
        let oldInfo: [String: Any] = ["Payload Image Info": ["URL": "InstallESDDmg.pkg", "id": "com.apple.pkg.InstallESDDmg"]]
        try PropertyListSerialization.data(fromPropertyList: oldInfo, format: .xml, options: 0).write(to: support.appendingPathComponent("InstallInfo.plist"))
        XCTAssertThrows { try LegacyInstaller.assemble(app: app, files: files) }
        let info: [String: Any] = ["Payload Image Info": ["URL": "InstallESD.dmg", "id": "com.apple.dmg.InstallESD", "version": "10.15.7"],
                                   "System Image Info": ["URL": "BaseSystem.dmg", "id": "com.apple.dmg.BaseSystem", "version": "10.15.7"]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: support.appendingPathComponent("InstallInfo.plist"))
        XCTAssertThrows { try LegacyInstaller.assemble(app: app, files: ["InstallESDDmg.pkg": files["InstallESDDmg.pkg"]!]) }
        try LegacyInstaller.assemble(app: app, files: files)
        XCTAssertEqual(try String(contentsOf: support.appendingPathComponent("InstallESD.dmg"), encoding: .utf8), "InstallESDDmg.pkg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: support.appendingPathComponent("BaseSystem.chunklist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("InstallAssistantAuto.pkg").path))
        let local = try XCTUnwrap(LocalInstaller.inspect(app.path))
        XCTAssertNil(local.preparationIssue)
        // These apps record only the version; any build of that version matches.
        XCTAssertTrue(local.matches(Installer(title: "macOS Catalina", version: "10.15.7", build: "19H15")))
        XCTAssertFalse(local.matches(Installer(title: "macOS Catalina", version: "10.15.6", build: "19G2021")))

        // OS X 10.10 – macOS 10.12: expanded InstallOS.pkg → app in Payload, InstallESD.dmg beside it.
        let pkg = folder.appendingPathComponent("dmg-expanded/InstallOS.pkg")
        let oldApp = pkg.appendingPathComponent("Payload/Install macOS Sierra.app")
        try FileManager.default.createDirectory(at: oldApp.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        XCTAssertNil(LegacyInstaller.diskImageContents(inExpanded: folder.appendingPathComponent("dmg-expanded")))   // nothing yet
        let oldTool = oldApp.appendingPathComponent("Contents/Resources/createinstallmedia")
        try Data("#!/bin/sh\n".utf8).write(to: oldTool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldTool.path)
        XCTAssertNil(LegacyInstaller.diskImageContents(inExpanded: folder.appendingPathComponent("dmg-expanded")))   // ESD missing
        try Data("esd".utf8).write(to: pkg.appendingPathComponent("InstallESD.dmg"))
        let found = try XCTUnwrap(LegacyInstaller.diskImageContents(inExpanded: folder.appendingPathComponent("dmg-expanded")))
        XCTAssertEqual(found.app.lastPathComponent, "Install macOS Sierra.app")
        try LegacyInstaller.assemble(app: found.app, installESD: found.esd)
        XCTAssertEqual(try String(contentsOf: oldApp.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg"), encoding: .utf8), "esd")
        XCTAssertNil(LocalInstaller.inspect(oldApp.path)?.preparationIssue)
        let images = AppleCatalog.diskImageInstallers
        XCTAssertEqual(images.map(\.version), ["10.12.6", "10.11.6", "10.10.5"])
        XCTAssertTrue(images.allSatisfy { $0.fromDiskImage && $0.assembledFromParts && !$0.offeredForThisMac && $0.packageURL?.host == "updates.cdn-apple.com" })
        XCTAssertFalse(Installer(title: "x", version: "15.0", build: "A", packageParts: [CatalogPart(name: "InstallAssistant.pkg", url: images[0].packageURL!, bytes: 1)]).assembledFromParts)

        // Mach-O architectures and the Rosetta hint.
        func be(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.bigEndian, Array.init) }
        func le(_ v: UInt32) -> [UInt8] { withUnsafeBytes(of: v.littleEndian, Array.init) }
        let thinIntel = Data(le(0xFEEDFACF) + le(0x0100_0007) + [UInt8](repeating: 0, count: 24))
        let fat = Data(be(0xCAFEBABE) + be(2) + be(0x0100_0007) + [UInt8](repeating: 0, count: 16) + be(0x0100_000C) + [UInt8](repeating: 0, count: 16))
        XCTAssertEqual(MachO.architectures(header: thinIntel), ["x86_64"])
        XCTAssertEqual(MachO.architectures(header: fat), ["x86_64", "arm64"])
        XCTAssertEqual(MachO.architectures(header: Data("#!/bin/sh".utf8)), [])
        let intelTool = folder.appendingPathComponent("intel"); try thinIntel.write(to: intelTool)
        let fatTool = folder.appendingPathComponent("fat"); try fat.write(to: fatTool)
        // --applicationpath: offered up to 10.13, deprecated from 10.14 (text taken from Apple's tools).
        let sierraTool = folder.appendingPathComponent("cim-sierra"), mojaveTool = folder.appendingPathComponent("cim-mojave")
        try Data("Usage: createinstallmedia --volume <path>\n--applicationpath, A path to copy of the OS installer application".utf8).write(to: sierraTool)
        try Data("WARNING: \"--applicationpath\" is deprecated in macOS 10.14 and greater.\n--volume, A path".utf8).write(to: mojaveTool)
        XCTAssertTrue(LegacyInstaller.needsApplicationPath(tool: sierraTool))
        XCTAssertFalse(LegacyInstaller.needsApplicationPath(tool: mojaveTool))
        XCTAssertFalse(LegacyInstaller.needsApplicationPath(tool: thinIntelTool(folder)))
        let job = TerminalJob(directory: folder.appendingPathComponent("job"))
        XCTAssertTrue(job.usbRootCommand(safety: "true", mount: "/Volumes/U", setup: nil, tool: "/A/cim", volume: "/Volumes/U", application: "/Applications/Install macOS Sierra.app")
            .contains("--volume '/Volumes/U' --applicationpath '/Applications/Install macOS Sierra.app' --nointeraction"))
        XCTAssertFalse(job.usbRootCommand(safety: "true", mount: "/Volumes/U", setup: nil, tool: "/A/cim", volume: "/Volumes/U").contains("applicationpath"))
        // Launch probe: a tool killed by SIGKILL at start counts as blocked; one that exits normally does not.
        let killed = folder.appendingPathComponent("killed.sh"), fine = folder.appendingPathComponent("fine.sh")
        try Data("#!/bin/sh\nkill -9 $$\n".utf8).write(to: killed); try Data("#!/bin/sh\nexit 1\n".utf8).write(to: fine)
        for tool in [killed, fine] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path) }
        XCTAssertTrue(MachO.killedAtLaunch(killed)); XCTAssertFalse(MachO.killedAtLaunch(fine))
        XCTAssertFalse(MachO.killedAtLaunch(folder.appendingPathComponent("missing")))
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
            "061-legacy": ["Packages": [["URL": "https://swcdn.apple.com/l/BaseSystem.dmg", "Size": 500, "IntegrityDataURL": "https://swcdn.apple.com/l/BaseSystem.dmg.integrityDataV1"],
                                        ["URL": "https://swcdn.apple.com/l/InstallESDDmg.pkg", "Size": 7000, "IntegrityDataURL": "https://swcdn.apple.com/l/InstallESDDmg.pkg.integrityDataV1"],
                                        ["URL": "https://swcdn.apple.com/l/OSInstall.mpkg", "Size": 9],
                                        ["URL": "https://swcdn.apple.com/l/BaseSystem.chunklist", "Size": 2],
                                        ["URL": "https://swcdn.apple.com/l/InstallAssistantAuto.pkg", "Size": 10]],
                           "Distributions": ["English": "https://swdist.apple.com/l.dist"]],
            "061-noBase": ["Packages": [["URL": "https://swcdn.apple.com/n/InstallESDDmg.pkg", "Size": 7000],
                                        ["URL": "https://swcdn.apple.com/n/InstallAssistantAuto.pkg", "Size": 10]],
                           "Distributions": ["English": "https://swdist.apple.com/n.dist"]],
            "update": ["Packages": [["URL": "https://swcdn.apple.com/x/Update.pkg", "Size": 1]],
                       "Distributions": ["English": "https://swdist.apple.com/y.dist"]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: catalog, format: .xml, options: 0)
        let products = AppleCatalog.products(fromCatalog: data)
        XCTAssertEqual(products.map(\.id), ["061-legacy", "142-50055"])
        let legacy = products[0]
        XCTAssertTrue(legacy.legacy)
        XCTAssertEqual(legacy.parts.map(\.name), ["InstallAssistantAuto.pkg", "InstallESDDmg.pkg", "BaseSystem.dmg", "BaseSystem.chunklist"])
        XCTAssertEqual(legacy.bytes, 7512)
        XCTAssertEqual(legacy.package.lastPathComponent, "InstallAssistantAuto.pkg")
        XCTAssertEqual(legacy.parts[1].integrity?.lastPathComponent, "InstallESDDmg.pkg.integrityDataV1")
        XCTAssertNil(legacy.parts[0].integrity)
        let modern = products[1]
        XCTAssertFalse(modern.legacy)
        XCTAssertEqual(modern.bytes, 17807147403)
        let catalina = try XCTUnwrap(AppleCatalog.describe(distribution: "<title>SU_TITLE</title><key>BUILD</key><string>19H15</string><key>VERSION</key><string>10.15.7</string>"))
        XCTAssertEqual(catalina.title, "macOS Catalina")
        XCTAssertEqual(AppleCatalog.marketingName(version: "10.13.6"), "macOS High Sierra")
        XCTAssertEqual(AppleCatalog.marketingName(version: "26.1"), "macOS Tahoe")
        XCTAssertNil(AppleCatalog.marketingName(version: "99.0"))
        let dist = "<title>macOS 27 Golden Gate</title><auxinfo><dict>\n<key>BUILD</key>\n<string>26B123</string>\n<key>VERSION</key>\n<string>27.2</string></dict></auxinfo>"
        let info = try XCTUnwrap(AppleCatalog.describe(distribution: dist))
        XCTAssertEqual(info.title, "macOS 27 Golden Gate"); XCTAssertEqual(info.version, "27.2"); XCTAssertEqual(info.build, "26B123")
        XCTAssertNil(AppleCatalog.describe(distribution: "<key>VERSION</key><string>27; rm</string><key>BUILD</key><string>X</string>"))
        let offered = [Installer(title: "macOS Sequoia", version: "15.7", build: "A", bytes: 1)]
        let fromCatalog = [Installer(title: "macOS Sequoia", version: "15.7", build: "A", bytes: 1, packageURL: modern.package, packageParts: modern.parts, offeredForThisMac: false),
                           Installer(title: "macOS 27 Golden Gate", version: "27.2", build: "26B123", bytes: 2, packageURL: modern.package, offeredForThisMac: false),
                           Installer(title: "macOS Catalina", version: "10.15.7", build: "19H15", bytes: 3, packageURL: legacy.package, packageParts: legacy.parts, offeredForThisMac: false)]
        let merged = AppleCatalog.merge(offered: offered, catalog: fromCatalog)
        XCTAssertEqual(merged.map(\.version), ["27.2", "15.7", "10.15.7"])
        XCTAssertFalse(merged[0].offeredForThisMac)
        XCTAssertTrue(merged[1].offeredForThisMac)
        XCTAssertNotNil(merged[1].packageURL)
        XCTAssertEqual(merged[1].packageParts, modern.parts)
        XCTAssertFalse(merged[1].assembledFromParts)
        XCTAssertTrue(merged[2].assembledFromParts)
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
    func testHostRelation() {
        func r(_ v: String, _ b: String) -> HostRelation { HostSystem.relation(version: v, build: b, hostVersion: "27.2.1", hostBuild: "26B131") }
        XCTAssertEqual(r("27.2.1", "26B131"), .installed)
        XCTAssertEqual(r("27.2.1", "26B8132"), .sameVersion)
        XCTAssertEqual(r("27.2", "26B8125"), .olderThanHost)
        XCTAssertEqual(r("26.4", "25E1"), .olderThanHost)
        XCTAssertEqual(r("27.3", "26C1"), .other)
        XCTAssertEqual(r("Manuell", "X"), .other)
        XCTAssertEqual(HostSystem.relation(version: "27.2", build: "A", hostVersion: "27.2.0", hostBuild: ""), .sameVersion)
        XCTAssertFalse(HostSystem.build.isEmpty)
        XCTAssertEqual(HostSystem.relation(version: HostSystem.version, build: HostSystem.build), .installed)
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
        XCTAssertTrue(text.contains("print -r -- \"$$\" > " + shellQuote(job.pidFile.path)))
        XCTAssertNil(job.shellRunning())                       // Terminal has not started the script yet
        try Data("\(getpid())\n".utf8).write(to: job.pidFile)
        XCTAssertEqual(job.shellRunning(), true)
        let ended = Process(); ended.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try ended.run(); ended.waitUntilExit()
        try Data("\(ended.processIdentifier)\n".utf8).write(to: job.pidFile)
        XCTAssertEqual(job.shellRunning(), false)              // Terminal window closed
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

func thinIntelTool(_ folder: URL) -> URL { folder.appendingPathComponent("intel") }
final class LockedValue: @unchecked Sendable {
    private let lock = NSLock(); private var smallest = Int64.max
    func min(_ value: Int64) { lock.lock(); smallest = Swift.min(smallest, value); lock.unlock() }
    var value: Int64 { lock.lock(); defer { lock.unlock() }; return smallest }
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
        try tests.testIntegrityAndLegacyInstaller()
        try tests.testDeviceDiscovery()
        try tests.testDevicePhotos()
        tests.testDFUGuide()
        tests.testVDM()
        tests.testFileVerify()
        try tests.testIPSWFlash()
        tests.testVersionValidation()
        tests.testHostRelation()
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
            // Real 10.13–10.15 product: Apple's integrity data verifies the stub package, which expands to an installer app.
            if let old = products.first(where: { $0.legacy && $0.parts[0].integrity != nil }) {
                let stub = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pkg")
                let expanded = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: stub); try? FileManager.default.removeItem(at: expanded) }
                _ = try await PackageDownload().run(old.parts[0].url, to: stub) { _, _ in }
                let (integrity, _) = try await URLSession.shared.data(from: old.parts[0].integrity!)
                XCTAssertEqual(try XCTUnwrap(Chunklist.parse(integrity)).verify(stub), .ok)
                // Interrupted download: cancel after the first megabytes, continue from the resume data, same bytes as Apple's.
                let resumed = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pkg")
                defer { try? FileManager.default.removeItem(at: resumed) }
                let first = PackageDownload()
                let stopped = LockedFlag()
                do {
                    _ = try await first.run(old.parts[0].url, to: resumed) { written, _ in
                        if written > 1_000_000, !stopped.value { stopped.set(); first.cancel() }
                    }
                    XCTAssertTrue(false)                          // must not finish
                } catch { XCTAssertTrue((error as? URLError)?.code == .cancelled) }
                let data = try XCTUnwrap(first.resumeData)          // handed over before run() returns, no waiting
                let offset = LockedValue()
                _ = try await PackageDownload().run(old.parts[0].url, to: resumed, resumeFrom: data) { written, _ in offset.min(written) }
                XCTAssertTrue(offset.value > 1_000_000)               // continued, did not start over
                XCTAssertEqual(try XCTUnwrap(Chunklist.parse(integrity)).verify(resumed), .ok)
                let expand = try await Command().run("/usr/sbin/pkgutil", ["--expand-full", stub.path, expanded.path], timeout: 120)
                XCTAssertEqual(expand.status, 0)
                let app = try XCTUnwrap(LegacyInstaller.stubApp(inExpanded: expanded))
                let infoData = try Data(contentsOf: app.appendingPathComponent("Contents/SharedSupport/InstallInfo.plist"))
                let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
                XCTAssertEqual((info["Payload Image Info"] as? [String: Any])?["URL"] as? String, "InstallESD.dmg")
                print("Live legacy installer: \(old.id) → \(app.lastPathComponent), \(products.filter(\.legacy).count) older installers in catalog")
            }
            for image in AppleCatalog.diskImageInstallers {
                var head = URLRequest(url: image.packageURL!); head.httpMethod = "HEAD"
                let (_, response) = try await URLSession.shared.data(for: head)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                XCTAssertEqual(response.expectedContentLength, Int64(image.bytes))
            }
            // Every Mac in Apple's macOS restore list must be in the model database.
            let (macFeed, _) = try await URLSession.shared.data(from: URL(string: "https://mesu.apple.com/assets/macos/com_apple_macOSIPSW/com_apple_macOSIPSW.xml")!)
            let feed = try PropertyListSerialization.propertyList(from: macFeed, format: nil) as! [String: Any]
            let macIDs = Set(((feed["MobileDeviceSoftwareVersionsByVersion"] as? [String: Any]) ?? [:]).values
                .flatMap { (($0 as? [String: Any])?["MobileDeviceSoftwareVersions"] as? [String: Any] ?? [:]).keys })
                .filter { !$0.hasPrefix("VirtualMac") }
            let modelFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/MacOSStudio/Resources/models.json")
            let knownMacs = Set(try JSONDecoder().decode([MacModel].self, from: Data(contentsOf: modelFile)).flatMap(\.identifiers))
            let missingMacs = macIDs.subtracting(knownMacs).sorted()
            print("Live Mac list: \(macIDs.count) Macs in Apple's macOS restore list, missing in database: \(missingMacs)")
            XCTAssertTrue(macIDs.count > 40 && missingMacs.isEmpty)
            XCTAssertEqual(Set(DeviceDiscovery.macs(fromRestoreFeed: macFeed).keys), macIDs)
            // Discovery against the real services: AppleDB names an iPad and a Mac like the built-in tables do.
            let (padJSON, _) = try await URLSession.shared.data(from: DeviceDiscovery.appleDBURL(for: "iPad19,2")!)
            XCTAssertEqual(DeviceDiscovery.displayName(try XCTUnwrap(DeviceDiscovery.record(fromAppleDB: padJSON, identifier: "iPad19,2"))), DeviceNames.name(for: "iPad19,2"))
            let (macJSON, _) = try await URLSession.shared.data(from: DeviceDiscovery.appleDBURL(for: "Mac18,2")!)
            let liveMac = DeviceDiscovery.macModel(identifier: "Mac18,2", record: try XCTUnwrap(DeviceDiscovery.record(fromAppleDB: macJSON, identifier: "Mac18,2")),
                                                   newestMacOS: DeviceDiscovery.macs(fromRestoreFeed: macFeed)["Mac18,2"] ?? "")
            print("Live discovery: Mac18,2 → \(liveMac.name), \(liveMac.category), \(liveMac.supported_versions)")
            XCTAssertEqual(liveMac.category, "iMac")
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
        // Opt-in check against a real, expanded Apple disk image package (pkgutil --expand-full InstallOS.pkg <dir>).
        if let path = ProcessInfo.processInfo.environment["STUDIO_EXPANDED_DMG_PKG"] {
            let root = URL(fileURLWithPath: path)
            let appURL: URL
            if let contents = LegacyInstaller.diskImageContents(inExpanded: root) {
                try LegacyInstaller.assemble(app: contents.app, installESD: contents.esd); appURL = contents.app
            } else {                                              // assembled by an earlier run
                let payload = try XCTUnwrap(FileManager.default.enumerator(atPath: path)?.compactMap { $0 as? String }.first { $0.hasSuffix("Payload") })
                appURL = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(payload), includingPropertiesForKeys: nil).first { $0.pathExtension == "app" })
            }
            let contents = (app: appURL, esd: appURL)
            let local = try XCTUnwrap(LocalInstaller.inspect(contents.app.path))
            XCTAssertNil(local.preparationIssue)
            let image = try XCTUnwrap(AppleCatalog.diskImageInstallers.first { local.matches($0) })
            let tool = contents.app.appendingPathComponent("Contents/Resources/createinstallmedia")
            XCTAssertTrue(LegacyInstaller.needsApplicationPath(tool: tool))
            print("Real createinstallmedia killed at launch on this Mac: \(MachO.killedAtLaunch(tool))")
            print("Real disk image installer: \(contents.app.lastPathComponent) matches \(image.title) \(image.version), archs \(MachO.architectures(of: tool).sorted()), --applicationpath needed")
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
        print("23 Swift test groups passed: local installers/trash, catalog, Apple catalog/gzip, integrity data/legacy installer, device discovery, serial lookup, firmware list, device photos, DFU guide, VDM, file verify, IPSW flasher, versions, host macOS, metrics, disk protection, quoting, terminal job, USB progress, USB root command, output, timeout, cancellation")
    }
}
