import Foundation
import IOKit
import StudioCore

/// Connected iPhone/iPad/iPod over USB. Normal-mode devices come from Apple's MobileDevice framework
/// (the one Finder uses, loaded at runtime); recovery and DFU devices are detected by their USB product ID.
@MainActor final class DeviceMonitor: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: String              // UDID
        var name: String
        var productType: String
        var version: String
        var paired: Bool
        var modelName: String { DeviceNames.name(for: productType) }
    }
    struct USBDevice: Identifiable, Equatable {
        let id: String
        let mode: DFUGuide.USBMode
        let serial: String
        var cpid: String? { DFUGuide.field("CPID", in: serial) }
        var ecid: String? { DFUGuide.field("ECID", in: serial) }
    }

    static let shared = DeviceMonitor()
    @Published private(set) var devices: [Device] = [] { didSet { autoCheck() } }
    @Published private(set) var usbDevices: [USBDevice] = []
    @Published private(set) var available = false
    @Published var message: String?
    @Published private(set) var working = false
    /// Devices seen on USB in normal mode that Apple's device service never reports – typically locked
    /// devices whose USB data is blocked (iOS "USB accessories" protection). Only buttons or unlocking help.
    @Published private(set) var blockedCount = 0
    private var normalSeen: [String: Date] = [:]
    private var readingOut: Set<String> = []

    private var md: MobileDevice?
    private var handles: [String: UnsafeMutableRawPointer] = [:]        // UDID → AMDeviceRef (retained)
    private var recoveryHandles: [UnsafeMutableRawPointer] = []          // AMRecoveryModeDeviceRef (retained)
    private var timer: Timer?
    private var started = false

    // MARK: Auto recovery ("Aktivieren" → plug in → recovery mode, no buttons)

    enum AutoState: Equatable {
        case off
        case waiting                    // "Stecke jetzt ein iPhone oder iPad an"
        case sending(String)
        case done(String)
        case failed(String)
    }
    @Published private(set) var auto: AutoState = .off
    private var autoHandled: Set<String> = []
    private var autoTask: Task<Void, Never>?

    func activateAuto() {
        start()
        autoHandled = []
        auto = .waiting
        autoCheck()
    }
    func deactivateAuto() { autoTask?.cancel(); autoTask = nil; auto = .off }

    /// Each device plugged in while active is sent once; unplugging re-arms it.
    /// A refused attempt (locked or not yet trusted) is retried every few seconds while the device stays
    /// plugged in, so it goes through as soon as the device is unlocked or "Vertrauen" is tapped.
    private func autoCheck() {
        autoHandled.formIntersection(devices.map(\.id))
        guard auto != .off, autoTask == nil else { return }
        guard let next = devices.first(where: { !autoHandled.contains($0.id) && !readingOut.contains($0.id) }) else {
            if auto == .waiting, !readingOut.isEmpty { auto = .sending("Gerät") }
            return
        }
        autoHandled.insert(next.id)
        if case .failed = auto {} else { auto = .sending(next.name == "iPhone/iPad" ? "Gerät" : next.name) }
        autoTask = Task { @MainActor in
            defer { autoTask = nil; autoCheck() }
            while working && !Task.isCancelled { try? await Task.sleep(nanoseconds: 300_000_000) }
            guard !Task.isCancelled, auto != .off else { return }
            guard let current = devices.first(where: { $0.id == next.id }) else { auto = .waiting; return }
            let ok = await enterRecovery(current, quiet: true)
            let text = lastRecoveryText
            guard !Task.isCancelled, auto != .off else { return }
            if ok { auto = .done(current.name == "iPhone/iPad" ? current.modelName : current.name); return }
            auto = .failed(text)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, auto != .off else { return }
            if devices.contains(where: { $0.id == next.id }) { autoHandled.remove(next.id) } else { auto = .waiting }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        md = MobileDevice.load()
        available = md != nil
        if let md {
            var notification: UnsafeMutableRawPointer?
            _ = md.subscribe(deviceCallback, 0, 0, nil, &notification)
            _ = md.registerRestore(ignoreDFU, recoveryConnected, ignoreDFU, recoveryDisconnected, 0, nil)   // DFU is detected over USB only
        }
        scanUSB()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in DeviceMonitor.shared.scanUSB() }
        }
    }

    // MARK: Normal mode

    fileprivate func attached(_ device: UnsafeMutableRawPointer) {
        guard let md, md.interfaceType(device) == 1,                       // 1 = USB, 2 = Wi-Fi
              let udid = md.copyIdentifier(device)?.takeRetainedValue() as String? else { return }
        if handles[udid] == nil { md.retainDevice(device); handles[udid] = device }
        if !devices.contains(where: { $0.id == udid }) {
            devices.append(Device(id: udid, name: "iPhone/iPad", productType: "", version: "", paired: false))
        }
        // lockdownd I/O (connect/pair/session) can block for a while on a locked device → off the main thread.
        // Auto recovery waits for this read-out so the two never talk to the device at the same time.
        readingOut.insert(udid)
        md.retainDevice(device)
        Task.detached { [md] in
            defer { md.releaseDevice(device) }
            var entry = Device(id: udid, name: "iPhone/iPad", productType: "", version: "", paired: false)
            if md.connect(device) == 0 {
                entry.paired = md.isPaired(device) == 1
                if entry.paired, md.validatePairing(device) == 0, md.startSession(device) == 0 {
                    entry.name = md.string(device, "DeviceName") ?? entry.name
                    entry.productType = md.string(device, "ProductType") ?? ""
                    entry.version = md.string(device, "ProductVersion") ?? ""
                    _ = md.stopSession(device)
                } else {
                    entry.productType = md.string(device, "ProductType") ?? ""
                    entry.version = md.string(device, "ProductVersion") ?? ""
                    entry.name = md.string(device, "DeviceName") ?? entry.name
                }
                _ = md.disconnect(device)
            }
            let result = entry
            await MainActor.run {
                DeviceMonitor.shared.readingOut.remove(udid)
                guard DeviceMonitor.shared.handles[udid] != nil else { DeviceMonitor.shared.autoCheck(); return }   // unplugged meanwhile
                DeviceMonitor.shared.devices.removeAll { $0.id == udid }
                DeviceMonitor.shared.devices.append(result)
            }
        }
    }
    fileprivate func detached(_ device: UnsafeMutableRawPointer) {
        guard let md, let udid = md.copyIdentifier(device)?.takeRetainedValue() as String? else { return }
        readingOut.remove(udid)
        devices.removeAll { $0.id == udid }
        if let handle = handles.removeValue(forKey: udid) { md.releaseDevice(handle) }
    }

    /// Restarts the device into recovery mode (laptop-and-cable screen). Needs a trusted (paired) device.
    /// Text of the last recovery attempt; with `quiet` it is not shown as an alert (the auto panel shows it).
    private(set) var lastRecoveryText = ""
    @discardableResult func enterRecovery(_ device: Device, quiet: Bool = false) async -> Bool {
        guard let md, let handle = handles[device.id], !working else { return false }
        let shown = message
        defer { lastRecoveryText = message ?? ""; if quiet { message = shown } }
        working = true
        defer { working = false }
        message = nil
        // Blocking lockdownd calls (slow on a locked device) run off the main thread.
        md.retainDevice(handle)
        let (connected, status) = await Task.detached { [md] () -> (Bool, Int32) in
            defer { md.releaseDevice(handle) }
            let connect = md.connect(handle)
            guard connect == 0 else { return (false, connect) }
            var status = md.enterRecovery(handle)
            if status != 0, md.validatePairing(handle) == 0, md.startSession(handle) == 0 {
                status = md.enterRecovery(handle)
                _ = md.stopSession(handle)
            }
            _ = md.disconnect(handle)
            return (true, status)
        }.value
        if !connected {
            message = "Verbindung zu „\(device.name)“ fehlgeschlagen (\(hex(status))). Gerät entsperren und erneut versuchen."
        } else if status == 0 {
            message = "„\(device.name)“ startet jetzt im Wiederherstellungsmodus neu. Auf dem Display erscheint gleich Laptop und Kabel."
        } else if !device.paired {
            message = "„\(device.name)“ vertraut diesem Mac noch nicht. Gerät entsperren, auf „Vertrauen“ tippen und erneut versuchen (\(hex(status)))."
        } else {
            message = "Das Gerät hat den Wiederherstellungsmodus abgelehnt (\(hex(status))). Gerät entsperren und erneut versuchen."
        }
        return status == 0
    }

    // MARK: Recovery / DFU

    fileprivate func recoveryAttached(_ device: UnsafeMutableRawPointer) {
        recoveryHandles.append(UnsafeMutableRawPointer(Unmanaged<AnyObject>.fromOpaque(device).retain().toOpaque()))
        scanUSB()
    }
    fileprivate func recoveryDetached(_ device: UnsafeMutableRawPointer) {
        if let index = recoveryHandles.firstIndex(of: device) {
            Unmanaged<AnyObject>.fromOpaque(recoveryHandles.remove(at: index)).release()
        }
        scanUSB()
    }

    /// Leaves recovery mode: sets auto-boot and restarts normally. Data on the device is not touched.
    func exitRecovery() async {
        guard !working else { return }
        guard let md else {
            message = "Der Gerätedienst ist auf diesem Mac nicht verfügbar. Bitte das Gerät mit den Tasten neu starten – die Anleitung steht unten."
            return
        }
        working = true
        defer { working = false }
        let targets = recoveryHandles
        guard !targets.isEmpty else { message = "Kein Gerät im Wiederherstellungsmodus gefunden. Kabel prüfen und kurz warten."; return }
        var failed = false
        for device in targets {
            if md.setAutoBoot(device, 1) != 0 { failed = true }
            if md.reboot(device) != 0 { failed = true }
        }
        message = failed ? "Das Gerät konnte nicht normal gestartet werden. Alternativ die Seitentaste (bzw. obere Taste) halten, bis das Apple-Logo erscheint."
                         : "Das Gerät startet jetzt normal. Das dauert etwa eine Minute."
    }

    /// Sends the USB-C VDM to a connected target Mac (Apple Silicon), via the app's own privileged helper.
    func sendMacVDM(reboot: Bool) async {
        guard !working else { return }
        working = true
        defer { working = false }
        guard let exe = Bundle.main.executablePath else { message = "Programmpfad nicht gefunden."; return }
        let shell = shellQuote(exe) + (reboot ? " --vdm-reboot" : " --vdm-dfu")
        let script = "do shell script " + appleScriptQuote(shell) + " with administrator privileges"
        do {
            let result = try await Command().run("/usr/bin/osascript", ["-e", script], timeout: 120)
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.contains("(-128)") { message = "Abgebrochen. Es wurde nichts gesendet."; return }
            message = output.isEmpty ? (result.status == 0 ? "Fertig." : "Fehlgeschlagen.") : output
        } catch { message = error.localizedDescription }
    }

    func scanUSB() {
        var found: [USBDevice] = []
        guard let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary? else { return }
        matching["idVendor"] = 0x05AC
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            let product = (IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue ?? 0
            guard let mode = DFUGuide.usbMode(productID: product) else { continue }
            let serial = IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            found.append(USBDevice(id: String(entryID), mode: mode, serial: serial))
        }
        // Normal-mode devices on USB that the device service has not reported for a few seconds are blocked.
        let now = Date()
        let normalIDs = Set(found.filter { $0.mode == .normal }.map(\.id))
        normalSeen = normalSeen.filter { normalIDs.contains($0.key) }
        for id in normalIDs where normalSeen[id] == nil { normalSeen[id] = now }
        let settled = normalSeen.values.filter { now.timeIntervalSince($0) > 4 }.count
        let blocked = available ? max(0, settled - devices.count) : 0
        if blocked != blockedCount { blockedCount = blocked }
        if !found.contains(where: { $0.mode == .recovery }) && !recoveryHandles.isEmpty {
            recoveryHandles.forEach { Unmanaged<AnyObject>.fromOpaque($0).release() }
            recoveryHandles.removeAll()
        }
        if found != usbDevices { usbDevices = found }
    }

    private func hex(_ status: Int32) -> String { "0x" + String(UInt32(bitPattern: status), radix: 16) }
}

// C callbacks from MobileDevice; delivered on the main run loop (subscribed from the main thread).
private let deviceCallback: MobileDevice.NotifyCallback = { info, _ in
    guard let info, let device = info.load(as: UnsafeMutableRawPointer?.self) else { return }
    let message = info.load(fromByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt32.self)
    let retained = Unmanaged<AnyObject>.fromOpaque(device).retain()
    DispatchQueue.main.async {
        let pointer = UnsafeMutableRawPointer(retained.toOpaque())
        if message == 1 { DeviceMonitor.shared.attached(pointer) } else if message == 2 { DeviceMonitor.shared.detached(pointer) }
        retained.release()
    }
}
private let ignoreDFU: MobileDevice.RestoreCallback = { _, _ in }
private let recoveryConnected: MobileDevice.RestoreCallback = { device, _ in
    guard let device else { return }
    let retained = Unmanaged<AnyObject>.fromOpaque(device).retain()
    DispatchQueue.main.async { DeviceMonitor.shared.recoveryAttached(UnsafeMutableRawPointer(retained.toOpaque())); retained.release() }
}
private let recoveryDisconnected: MobileDevice.RestoreCallback = { device, _ in
    guard let device else { return }
    DispatchQueue.main.async { DeviceMonitor.shared.recoveryDetached(device) }
}

/// Function table for the private MobileDevice framework, resolved with dlsym. If anything is missing the
/// framework is treated as unavailable and only USB detection works.
struct MobileDevice: @unchecked Sendable {
    typealias NotifyCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias RestoreCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Subscribe = @convention(c) (NotifyCallback, UInt32, UInt32, UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Int32
    typealias RegisterRestore = @convention(c) (RestoreCallback, RestoreCallback, RestoreCallback, RestoreCallback, UInt32, UnsafeMutableRawPointer?) -> Int32
    typealias DeviceCall = @convention(c) (UnsafeMutableRawPointer?) -> Int32
    typealias DeviceVoid = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias CopyString = @convention(c) (UnsafeMutableRawPointer?) -> Unmanaged<CFString>?
    typealias CopyValue = @convention(c) (UnsafeMutableRawPointer?, CFString?, CFString) -> Unmanaged<CFTypeRef>?
    typealias SetAutoBoot = @convention(c) (UnsafeMutableRawPointer?, UInt8) -> Int32

    let subscribe: Subscribe
    let registerRestore: RegisterRestore
    let copyIdentifier: CopyString
    let interfaceType: DeviceCall
    let connect: DeviceCall
    let disconnect: DeviceCall
    let isPaired: DeviceCall
    let validatePairing: DeviceCall
    let startSession: DeviceCall
    let stopSession: DeviceCall
    let enterRecovery: DeviceCall
    let copyValue: CopyValue
    let setAutoBoot: SetAutoBoot
    let reboot: DeviceCall
    let retain: DeviceVoid
    let release: DeviceVoid
    func retainDevice(_ d: UnsafeMutableRawPointer) { retain(d) }
    func releaseDevice(_ d: UnsafeMutableRawPointer) { release(d) }

    func string(_ device: UnsafeMutableRawPointer, _ key: String) -> String? {
        copyValue(device, nil, key as CFString)?.takeRetainedValue() as? String
    }

    static func load() -> MobileDevice? {
        let paths = ["/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice",
                     "/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice"]
        guard let handle = paths.lazy.compactMap({ dlopen($0, RTLD_NOW) }).first else { return nil }
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let subscribe = symbol("AMDeviceNotificationSubscribe", Subscribe.self),
              let registerRestore = symbol("AMRestoreRegisterForDeviceNotifications", RegisterRestore.self),
              let copyIdentifier = symbol("AMDeviceCopyDeviceIdentifier", CopyString.self),
              let interfaceType = symbol("AMDeviceGetInterfaceType", DeviceCall.self),
              let connect = symbol("AMDeviceConnect", DeviceCall.self),
              let disconnect = symbol("AMDeviceDisconnect", DeviceCall.self),
              let isPaired = symbol("AMDeviceIsPaired", DeviceCall.self),
              let validatePairing = symbol("AMDeviceValidatePairing", DeviceCall.self),
              let startSession = symbol("AMDeviceStartSession", DeviceCall.self),
              let stopSession = symbol("AMDeviceStopSession", DeviceCall.self),
              let enterRecovery = symbol("AMDeviceEnterRecovery", DeviceCall.self),
              let copyValue = symbol("AMDeviceCopyValue", CopyValue.self),
              let setAutoBoot = symbol("AMRecoveryModeDeviceSetAutoBoot", SetAutoBoot.self),
              let reboot = symbol("AMRecoveryModeDeviceReboot", DeviceCall.self),
              let retain = symbol("AMDeviceRetain", DeviceVoid.self),
              let release = symbol("AMDeviceRelease", DeviceVoid.self)
        else { return nil }
        return MobileDevice(subscribe: subscribe, registerRestore: registerRestore, copyIdentifier: copyIdentifier,
                            interfaceType: interfaceType, connect: connect, disconnect: disconnect, isPaired: isPaired,
                            validatePairing: validatePairing, startSession: startSession, stopSession: stopSession,
                            enterRecovery: enterRecovery, copyValue: copyValue, setAutoBoot: setAutoBoot, reboot: reboot,
                            retain: retain, release: release)
    }
}
