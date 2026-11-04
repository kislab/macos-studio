import Foundation

/// Button sequences for DFU mode. DFU can only be entered with the device's buttons; the app guides the timing
/// and detects success over USB (Apple vendor 0x05AC, product 0x1227).
public enum DFUGuide {
    public enum Method: String, CaseIterable, Identifiable, Sendable {
        case faceIDiPhone, iPhone7, homeButtoniPhone, faceIDiPad, homeButtoniPad
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .faceIDiPhone: "iPhone 8 und neuer (auch SE 2./3. Gen.)"
            case .iPhone7: "iPhone 7 / 7 Plus"
            case .homeButtoniPhone: "iPhone 6s und älter, SE (1. Gen.), iPod touch"
            case .faceIDiPad: "iPad ohne Home-Taste"
            case .homeButtoniPad: "iPad mit Home-Taste"
            }
        }
    }
    public struct Step: Equatable, Sendable {
        public let text: String
        public let seconds: Int
    }

    public static func method(for identifier: String) -> Method? {
        let parts = identifier.drop { !$0.isNumber }.split(separator: ",").compactMap { Int($0) }
        guard let major = parts.first, ["iPhone", "iPad", "iPod"].contains(where: { identifier.hasPrefix($0) }) else { return nil }
        switch DeviceNames.family(of: identifier) {
        case .iPhone: return major <= 8 ? .homeButtoniPhone : major == 9 ? .iPhone7 : .faceIDiPhone
        case .iPad: return DeviceNames.design(of: identifier) == .padHomeButton ? .homeButtoniPad : .faceIDiPad
        case .iPod: return .homeButtoniPhone
        }
    }

    public static func steps(for method: Method) -> [Step] {
        switch method {
        case .faceIDiPhone: [
            Step(text: "Lauter kurz drücken und loslassen, Leiser kurz drücken und loslassen, dann sofort die Seitentaste gedrückt halten – bis der Bildschirm schwarz wird.", seconds: 10),
            Step(text: "Seitentaste weiter halten und zusätzlich Leiser gedrückt halten.", seconds: 5),
            Step(text: "Seitentaste loslassen, Leiser weiter gedrückt halten.", seconds: 10)]
        case .iPhone7: [
            Step(text: "Seitentaste und Leiser gleichzeitig gedrückt halten.", seconds: 8),
            Step(text: "Seitentaste loslassen, Leiser weiter gedrückt halten.", seconds: 10)]
        case .homeButtoniPhone: [
            Step(text: "Home-Taste und Seiten- bzw. obere Taste gleichzeitig gedrückt halten.", seconds: 8),
            Step(text: "Seiten- bzw. obere Taste loslassen, Home-Taste weiter gedrückt halten.", seconds: 10)]
        case .faceIDiPad: [
            Step(text: "Die Lautstärketaste näher an der oberen Taste kurz drücken, dann die andere Lautstärketaste kurz drücken, dann sofort die obere Taste gedrückt halten – bis der Bildschirm schwarz wird.", seconds: 10),
            Step(text: "Obere Taste weiter halten und zusätzlich die Lautstärketaste weiter weg von der oberen Taste gedrückt halten.", seconds: 5),
            Step(text: "Obere Taste loslassen, die Lautstärketaste weiter gedrückt halten.", seconds: 10)]
        case .homeButtoniPad: [
            Step(text: "Home-Taste und obere Taste gleichzeitig gedrückt halten.", seconds: 8),
            Step(text: "Obere Taste loslassen, Home-Taste weiter gedrückt halten.", seconds: 10)]
        }
    }

    /// USB product IDs Apple devices report in the boot ROM / iBoot.
    public enum USBMode: Equatable, Sendable { case dfu, recovery }
    public static func usbMode(productID: Int) -> USBMode? {
        switch productID {
        case 0x1227: .dfu
        case 0x1280...0x1283: .recovery
        default: nil
        }
    }
    /// Values from iBoot's USB serial string, e.g. "CPID:8030 CPRV:11 ... ECID:001A2B3C SRNM:[F2LXXXX]".
    public static func field(_ key: String, in serial: String) -> String? {
        guard let range = serial.range(of: key + ":") else { return nil }
        let rest = serial[range.upperBound...]
        let value = rest.hasPrefix("[") ? rest.dropFirst().prefix { $0 != "]" } : rest.prefix { $0 != " " }
        return value.isEmpty ? nil : String(value)
    }
}
