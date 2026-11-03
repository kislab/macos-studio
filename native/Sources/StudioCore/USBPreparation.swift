import Foundation

/// APFS conversion is limited to a single-volume, single-store external USB container.
public struct USBPreparation {
    public let container: String
    public let containerUUID: String
    public let store: String
    public let storeUUID: String
    public let volumeUUID: String
    public init?(target: ExternalDisk, container: [String: Any], storeInfo: [String: Any]) {
        guard let reference = container["ContainerReference"] as? String,
              let uuid = container["APFSContainerUUID"] as? String,
              let volumes = container["Volumes"] as? [[String: Any]], volumes.count == 1,
              volumes[0]["DeviceIdentifier"] as? String == target.identifier,
              volumes[0]["APFSVolumeUUID"] as? String == target.uuid,
              let stores = container["PhysicalStores"] as? [[String: Any]], stores.count == 1,
              let store = stores[0]["DeviceIdentifier"] as? String,
              let storeUUID = stores[0]["DiskUUID"] as? String,
              storeInfo["DeviceIdentifier"] as? String == store,
              storeInfo["DiskUUID"] as? String == storeUUID,
              storeInfo["Internal"] as? Bool == false,
              storeInfo["BusProtocol"] as? String == "USB",
              !uuid.isEmpty, !storeUUID.isEmpty else { return nil }
        self.container = reference; containerUUID = uuid
        self.store = store; self.storeUUID = storeUUID; volumeUUID = target.uuid
    }
    public func shellCommand(name: String, mount: String) -> String {
        func extract(_ path: String) -> String {
            "$(/usr/bin/printf '%s' \"$apfs\" | /usr/bin/plutil -extract " + shellQuote("Containers.0." + path) + " raw -o - -)"
        }
        let oneStore = "! /usr/bin/printf '%s' \"$apfs\" | /usr/bin/plutil -extract Containers.0.PhysicalStores.1 xml1 -o - - >/dev/null 2>&1"
        let oneVolume = "! /usr/bin/printf '%s' \"$apfs\" | /usr/bin/plutil -extract Containers.0.Volumes.1 xml1 -o - - >/dev/null 2>&1"
        return "apfs=$(/usr/sbin/diskutil apfs list -plist " + shellQuote(container) + ") && "
            + "test \"" + extract("APFSContainerUUID") + "\" = " + shellQuote(containerUUID)
            + " && test \"" + extract("PhysicalStores.0.DiskUUID") + "\" = " + shellQuote(storeUUID)
            + " && test \"" + extract("PhysicalStores.0.DeviceIdentifier") + "\" = " + shellQuote(store)
            + " && test \"" + extract("Volumes.0.APFSVolumeUUID") + "\" = " + shellQuote(volumeUUID)
            + " && test \"$(/usr/sbin/diskutil info -plist " + shellQuote(store) + " | /usr/bin/plutil -extract Internal raw -o - -)\" = false"
            + " && test \"$(/usr/sbin/diskutil info -plist " + shellQuote(store) + " | /usr/bin/plutil -extract BusProtocol raw -o - -)\" = USB"
            + " && " + oneStore + " && " + oneVolume
            + " && /usr/sbin/diskutil apfs deleteContainer " + shellQuote(container) + " JHFS+ " + shellQuote(name) + " 0"
            + " && test \"$(/usr/sbin/diskutil info -plist " + shellQuote(store) + " | /usr/bin/plutil -extract FilesystemType raw -o - -)\" = hfs"
            + " && test \"$(/usr/sbin/diskutil info -plist " + shellQuote(store) + " | /usr/bin/plutil -extract MountPoint raw -o - -)\" = " + shellQuote(mount)
    }
}
