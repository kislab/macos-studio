import Foundation
import IOKit
import StudioCore

/// Function table of the private AppleHPM plugin interface (from AsahiLinux/macvdmtool, Apache-2.0).
/// Layout mirrors the C struct: IUnknown guts, two uint16, then Read/Write/Command and three unused slots.
struct AppleHPMLib {
    var _reserved: UnsafeMutableRawPointer?
    var QueryInterface: (@convention(c) (UnsafeMutableRawPointer?, CFUUIDBytes, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT)?
    var AddRef: (@convention(c) (UnsafeMutableRawPointer?) -> ULONG)?
    var Release: (@convention(c) (UnsafeMutableRawPointer?) -> ULONG)?
    var field_20: UInt16
    var field_22: UInt16
    var Read: (@convention(c) (UnsafeMutableRawPointer?, UInt64, UInt8, UnsafeMutableRawPointer?, UInt64, UInt32, UnsafeMutablePointer<UInt64>?) -> IOReturn)?
    var Write: (@convention(c) (UnsafeMutableRawPointer?, UInt64, UInt8, UnsafeRawPointer?, UInt64, UInt32) -> IOReturn)?
    var Command: (@convention(c) (UnsafeMutableRawPointer?, UInt64, UInt32, UInt32) -> IOReturn)?
    var field_40: (@convention(c) () -> IOReturn)?
    var field_48: (@convention(c) () -> IOReturn)?
    var field_50: (@convention(c) () -> IOReturn)?
}

/// Runs as root (invoked via admin privileges) and sends the DFU or reboot VDM to the connected target Mac.
/// Returns a process exit code; prints one status line. Does nothing unless a device is actually connected.
enum VDMTool {
    struct Fail: Error { let message: String }

    static func run(reboot: Bool) -> Int32 {
        do {
            let key = try boardKey()
            let (plugin, device) = try openDevice()
            defer {
                _ = command(device, chip: 0, cmd: VDM.dbma, args: [0x00])   // leave DBMa mode
                IODestroyPlugInInterface(plugin)
            }
            // Connection check (register 0x3f, bit 0).
            let conn = try read(device, chip: 0, reg: 0x3f)
            guard (conn.first ?? 0) & 1 == 1 else { throw Fail(message: String(localized: "Kein Gerät am DFU-Port erkannt. Beide Macs über den DFU-Port mit einem USB-C-/Thunderbolt-Kabel verbinden.")) }
            // Enter debug (DBMa) mode if not already there.
            var status = string(try read(device, chip: 0, reg: 0x03))
            if status != "DBMa" {
                if command(device, chip: 0, cmd: VDM.lock, args: VDM.keyBytes(fromBoardName: key)) != 0 {
                    _ = command(device, chip: 0, cmd: VDM.gaid, args: [])
                    _ = command(device, chip: 0, cmd: VDM.lock, args: VDM.keyBytes(fromBoardName: key))
                }
                _ = command(device, chip: 0, cmd: VDM.dbma, args: [0x01])
                status = string(try read(device, chip: 0, reg: 0x03))
                guard status == "DBMa" else { throw Fail(message: String(localized: "Der USB-C-Controller ließ sich nicht entsperren (Status \"\(status)\"). Nur Apple Silicon, nur am DFU-Port.")) }
            }
            try sendVDM(device, words: reboot ? VDM.rebootWords : VDM.dfuWords)
            print(reboot ? String(localized: "OK: Ziel-Mac startet neu.") : String(localized: "OK: Ziel-Mac ist jetzt im DFU-Modus."))
            return 0
        } catch let error as Fail {
            print(error.message)
            return 2
        } catch {
            print(String(localized: "Unerwarteter Fehler: \(error.localizedDescription)"))
            return 3
        }
    }

    // MARK: Device I/O (mirrors macvdmtool's helpers)

    private static func read(_ device: UnsafeMutablePointer<UnsafeMutablePointer<AppleHPMLib>>, chip: UInt64, reg: UInt8) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 64)
        var readLen: UInt64 = 0
        let result = buffer.withUnsafeMutableBytes { raw in
            device.pointee.pointee.Read!(UnsafeMutableRawPointer(device), chip, reg, raw.baseAddress, 64, 0, &readLen)
        }
        guard result == 0 else { throw Fail(message: String(localized: "Lesen von Register \(String(reg)) fehlgeschlagen (0x\(String(UInt32(bitPattern: result), radix: 16))).")) }
        return buffer
    }
    private static func command(_ device: UnsafeMutablePointer<UnsafeMutablePointer<AppleHPMLib>>, chip: UInt64, cmd: UInt32, args: [UInt8]) -> Int {
        if !args.isEmpty {
            _ = args.withUnsafeBytes { raw in
                device.pointee.pointee.Write!(UnsafeMutableRawPointer(device), chip, 9, raw.baseAddress, UInt64(args.count), 0)
            }
        }
        let ret = device.pointee.pointee.Command!(UnsafeMutableRawPointer(device), chip, cmd, 0)
        if ret != 0 { return -1 }
        guard let res = try? read(device, chip: chip, reg: 9) else { return -1 }
        return Int(res.first ?? 0) & 0xf
    }
    private static func sendVDM(_ device: UnsafeMutablePointer<UnsafeMutablePointer<AppleHPMLib>>, words: [UInt32]) throws {
        let before = try read(device, chip: 0, reg: 0x4d)
        let rxst = before.first ?? 0
        guard command(device, chip: 0, cmd: VDM.vdms, args: VDM.args(for: words)) == 0 else {
            throw Fail(message: String(localized: "Das VDM konnte nicht gesendet werden."))
        }
        var reply = before
        var changed = false
        for _ in 0..<16 {
            reply = try read(device, chip: 0, reg: 0x4d)
            if (reply.first ?? 0) != rxst { changed = true; break }
        }
        guard changed else { throw Fail(message: String(localized: "Keine Antwort auf das VDM. Kabel am DFU-Port prüfen.")) }
        let header = UInt32(reply[1]) | (UInt32(reply[2]) << 8) | (UInt32(reply[3]) << 16) | (UInt32(reply[4]) << 24)
        guard header == VDM.replyHeader(for: words) else {
            throw Fail(message: String(localized: "Das Gerät lehnte das VDM ab (Antwort 0x\(String(header, radix: 16)))."))
        }
    }
    private static func string(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    // MARK: Service lookup

    private static func uuid(_ b: [UInt8]) -> CFUUID {
        CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    }
    private static func openDevice() throws -> (UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>, UnsafeMutablePointer<UnsafeMutablePointer<AppleHPMLib>>) {
        guard let matching = IOServiceMatching("AppleHPM") else { throw Fail(message: String(localized: "AppleHPM nicht gefunden. Dieses Gerät unterstützt die Funktion nicht (nur Apple Silicon).")) }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { throw Fail(message: String(localized: "USB-C-Controller nicht erreichbar.")) }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let ridRef = IORegistryEntryCreateCFProperty(service, "RID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let rid = ridRef as? Int, rid == 0 else { continue }
            let hpmType = uuid([0x12, 0xA1, 0xDC, 0xCF, 0xCF, 0x7A, 0x47, 0x75, 0xBE, 0xE5, 0x9C, 0x43, 0x19, 0xF4, 0xCD, 0x2B])
            let plugInID = uuid([0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F])
            let hpmInterface = uuid([0xC1, 0x3A, 0xCD, 0xD9, 0x20, 0x9E, 0x4B, 0x01, 0xB7, 0xBE, 0xE0, 0x5C, 0xD8, 0x83, 0xC7, 0xB1])
            var plugin: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
            var score: Int32 = 0
            guard IOCreatePlugInInterfaceForService(service, hpmType, plugInID, &plugin, &score) == kIOReturnSuccess, let plugin else {
                throw Fail(message: String(localized: "AppleHPM-Schnittstelle konnte nicht geöffnet werden (Administratorrechte nötig)."))
            }
            var deviceRaw: UnsafeMutableRawPointer?
            let qi = plugin.pointee!.pointee.QueryInterface(UnsafeMutableRawPointer(plugin), CFUUIDGetUUIDBytes(hpmInterface), &deviceRaw)
            guard qi == S_OK, let deviceRaw else {
                IODestroyPlugInInterface(plugin)
                throw Fail(message: String(localized: "AppleHPM-Schnittstelle nicht verfügbar."))
            }
            let device = deviceRaw.assumingMemoryBound(to: UnsafeMutablePointer<AppleHPMLib>.self)
            return (plugin, device)
        }
        throw Fail(message: String(localized: "Kein passender USB-C-Controller (RID 0) gefunden. Nur Apple Silicon."))
    }
    private static func boardKey() throws -> [UInt8] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { throw Fail(message: String(localized: "Mac-Modell konnte nicht gelesen werden.")) }
        defer { IOObjectRelease(service) }
        var name = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(service, &name) == KERN_SUCCESS else { throw Fail(message: String(localized: "Mac-Modell konnte nicht gelesen werden.")) }
        return name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    }

    /// True on Apple Silicon (the VDM path only exists there).
    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }
}
