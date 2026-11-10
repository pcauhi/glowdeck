import Foundation

/// Packet builders for ROBOBLOQ / DX-Light USB light bars (HID 1A86:FE07).
///
/// Every command is one 64-byte HID output report:
///     "RB" | len | seq | action | payload… | checksum (sum of all previous bytes, mod 256)
/// Per-LED frames use an "SC" header with a 16-bit length and may span several reports.
///
/// Reverse-engineered by the community, see:
///   github.com/tanmaster/light-control-rs (docs/protocol.md)
///   github.com/hacmiu/synclight-pro (PROTOCOL.md)
///   github.com/jakebuild/synclight
public enum RobobloqProtocol {
    public static let vendorID = 0x1A86
    public static let productID = 0xFE07
    public static let usagePage = 0xFF00
    public static let reportSize = 64
    /// Highest LED index the firmware accepts in a range.
    public static let maxLED: UInt8 = 254
    /// Most LED groups the official app puts in one frame.
    public static let maxFrameGroups = 50

    public enum Action: UInt8 {
        case syncScreen = 0x80
        case readDeviceInfo = 0x82
        case ledEffect = 0x85
        case sectionLED = 0x86
        case brightness = 0x87
        case dynamicSpeed = 0x8A
        case turnOff = 0x97
    }

    public static func checksum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        bytes.reduce(0) { $0 &+ $1 }
    }

    public static func packet(_ action: Action, seq: UInt8, payload: [UInt8] = []) -> [UInt8] {
        var p: [UInt8] = [0x52, 0x42, UInt8(6 + payload.count), seq, action.rawValue]
        p += payload
        p.append(checksum(p))
        return p
    }

    /// Whole strip one colour; LEDs past the strip are blanked like the official app does.
    public static func solid(_ c: RGB, ledCount: Int, seq: UInt8) -> [UInt8] {
        let n = UInt8(clamping: ledCount)
        let payload: [UInt8] = (n == 0 || n >= maxLED)
            ? [1, c.r, c.g, c.b, maxLED]
            : [1, c.r, c.g, c.b, n, n + 1, 0, 0, 0, maxLED]
        return packet(.sectionLED, seq: seq, payload: payload)
    }

    public static func off(seq: UInt8) -> [UInt8] {
        packet(.sectionLED, seq: seq, payload: [1, 0, 0, 0, maxLED])
    }

    /// value 0...1 → 5...100 (firmware minimum is 5)
    public static func brightness(_ value: Double, seq: UInt8) -> [UInt8] {
        packet(.brightness, seq: seq, payload: [UInt8(max(5, min(100, (value * 100).rounded())))])
    }

    /// speed 0...1 where 1 is fastest. The firmware counts down: 0 fast, 100 slow.
    public static func effectSpeed(_ speed: Double, seq: UInt8) -> [UInt8] {
        let v = 100 - (speed * 100).rounded()
        return packet(.dynamicSpeed, seq: seq, payload: [UInt8(max(5, min(100, v)))])
    }

    /// Built-in "dynamic" effects 0…6.
    public static func builtinEffect(_ index: UInt8, seq: UInt8) -> [UInt8] {
        packet(.ledEffect, seq: seq, payload: [2, index])
    }

    public static func readInfo(seq: UInt8) -> [UInt8] {
        packet(.readDeviceInfo, seq: seq)
    }

    /// One colour per LED, merged into at most `maxFrameGroups` ranges.
    public static func frame(_ colors: [RGB], seq: UInt8) -> [UInt8] {
        let n = min(colors.count, Int(maxLED))
        guard n > 0 else { return [] }
        let k = min(n, maxFrameGroups)
        var groups: [UInt8] = []
        for j in 0..<k {
            let s = j * n / k, e = (j + 1) * n / k
            let avg = RGB.average(Array(colors[s..<e]))
            groups += [UInt8(s + 1), avg.r, avg.g, avg.b, UInt8(e)]
        }
        let len = 7 + groups.count
        var p: [UInt8] = [0x53, 0x43, UInt8(len >> 8), UInt8(len & 0xFF), seq, Action.syncScreen.rawValue]
        p += groups
        p.append(checksum(p))
        return p
    }

    /// Split a packet into zero-padded 64-byte reports.
    public static func reports(_ packet: [UInt8]) -> [[UInt8]] {
        stride(from: 0, to: packet.count, by: reportSize).map { i in
            var r = Array(packet[i..<min(i + reportSize, packet.count)])
            r += [UInt8](repeating: 0, count: reportSize - r.count)
            return r
        }
    }

    public struct DeviceInfo: Equatable {
        public var ledCount: Int
        public var firmware: String
    }

    /// Parse a readDeviceInfo reply.
    public static func parseInfo(_ r: [UInt8]) -> DeviceInfo? {
        guard r.count > 23, r[0] == 0x52, r[1] == 0x42, r[4] == Action.readDeviceInfo.rawValue else { return nil }
        return DeviceInfo(ledCount: Int(r[11]), firmware: "\(r[21]).\(r[22]).\(r[23])")
    }

    public static let builtinEffects: [NativeEffect] = (0..<7).map {
        NativeEffect(id: "rb.\($0)", name: "Built-in \($0 + 1)")
    }
}
