import Foundation

/// USB-C Vendor-Defined Messages to put an Apple Silicon target Mac into DFU or reboot it,
/// reimplemented from AsahiLinux/macvdmtool (Apache-2.0) for use with Apple's AppleHPM interface.
/// Pure byte helpers here are unit-tested; the IOKit calls live in the app's privileged helper.
public enum VDM {
    /// Four-character command code packed big-endian, as clang multi-char literals ('VDMs', 'DBMa', …).
    public static func fourCC(_ code: String) -> UInt32 {
        code.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    public static let vdms = fourCC("VDMs")
    public static let lock = fourCC("LOCK")
    public static let dbma = fourCC("DBMa")
    public static let gaid = fourCC("Gaid")

    public static let dfuWords: [UInt32] = [0x5ac8012, 0x106, 0x80010000]
    public static let rebootWords: [UInt32] = [0x5ac8012, 0x105, 0x80000000]

    /// VDM argument buffer: header byte ((3<<4)|count) followed by each word in host (little-endian) order.
    public static func args(for words: [UInt32]) -> [UInt8] {
        var bytes: [UInt8] = [UInt8((3 << 4) | (words.count & 0x0f))]
        for word in words {
            bytes.append(UInt8(word & 0xff))
            bytes.append(UInt8((word >> 8) & 0xff))
            bytes.append(UInt8((word >> 16) & 0xff))
            bytes.append(UInt8((word >> 24) & 0xff))
        }
        return bytes
    }
    /// Expected reply VDM header for a request (first word | 0x40).
    public static func replyHeader(for words: [UInt32]) -> UInt32 { words[0] | 0x40 }

    /// Unlock key: first four characters of the Mac's board name packed big-endian, then sent little-endian.
    public static func key(fromBoardName name: [UInt8]) -> UInt32 {
        func at(_ i: Int) -> UInt32 { i < name.count ? UInt32(name[i]) : 0 }
        return (at(0) << 24) | (at(1) << 16) | (at(2) << 8) | at(3)
    }
    public static func keyBytes(fromBoardName name: [UInt8]) -> [UInt8] {
        let k = key(fromBoardName: name)
        return [UInt8(k & 0xff), UInt8((k >> 8) & 0xff), UInt8((k >> 16) & 0xff), UInt8((k >> 24) & 0xff)]
    }
}
