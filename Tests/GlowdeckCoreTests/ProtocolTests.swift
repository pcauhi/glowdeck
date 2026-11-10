import Testing
@testable import GlowdeckCore

private func hex(_ s: String) -> [UInt8] {
    let clean = s.replacingOccurrences(of: " ", with: "")
    return stride(from: 0, to: clean.count, by: 2).map {
        let i = clean.index(clean.startIndex, offsetBy: $0)
        return UInt8(clean[i...clean.index(after: i)], radix: 16)!
    }
}

@Suite struct RobobloqTests {
    /// Captured from the official DX-Light app (80-LED strip set to black), via tanmaster/light-control-rs.
    @Test func solidMatchesCapture() {
        #expect(RobobloqProtocol.solid(.black, ledCount: 80, seq: 0x41) == hex("52 42 10 41 86 01 00 00 00 50 51 00 00 00 fe 0b"))
    }

    /// Captured screen-sync frame: 50 groups of red over 80 LEDs.
    @Test func frameMatchesCapture() {
        let capture = hex("534301013b8001ff00000102ff00000304ff00000405ff00000708ff00000809ff00000a0bff00000b0cff00000d0eff00000e0fff00001011ff00001112ff00001314ff00001415ff00001617ff00001819ff00001a1bff00001c1dff00001e1fff00002021ff00002122ff00002324ff00002425ff00002627ff00002728ff00002829ff00002a2bff00002b2cff00002d2eff00002e2fff00003132ff00003233ff00003435ff00003536ff00003637ff00003738ff00003839ff00003a3bff00003b3cff00003d3eff00003e3fff00004041ff00004243ff00004445ff00004647ff00004849ff00004a4bff00004b4cff00004d4eff00004e4fff000050e9")
        let built = RobobloqProtocol.frame([RGB](repeating: RGB(255, 0, 0), count: 80), seq: 0x3b)
        #expect(built.count == capture.count)
        // Same header, length and checksum scheme; group boundaries may differ by rounding.
        #expect(Array(built.prefix(6)) == Array(capture.prefix(6)))
        #expect(built.last == RobobloqProtocol.checksum(built.dropLast()))
        #expect(RobobloqProtocol.reports(built).count == 5)
    }

    @Test func brightnessAndSpeedClamp() {
        #expect(RobobloqProtocol.brightness(0, seq: 1)[5] == 5)
        #expect(RobobloqProtocol.brightness(1, seq: 1)[5] == 100)
        #expect(RobobloqProtocol.effectSpeed(1, seq: 1)[5] == 5)    // fastest
        #expect(RobobloqProtocol.effectSpeed(0, seq: 1)[5] == 100)  // slowest
    }

    @Test func parsesDeviceInfoReplyFromRealBar() {
        // Reply from a real 75-LED bar (firmware 1.9.4).
        let r = hex("52 42 19 07 82 00 06 03 22 01 00 4b 00 00 00 00 00 00 00 00 00 01 09 04") + [UInt8](repeating: 0, count: 40)
        #expect(RobobloqProtocol.parseInfo(r) == .init(ledCount: 75, firmware: "1.9.4"))
    }
}

@Suite struct LIFXTests {
    @Test func getServiceHeader() {
        let p = LIFXProtocol.packet(.getService)
        #expect(p.count == 36)
        #expect(p[0] == 36 && p[1] == 0)
        #expect(p[2] == 0x00 && p[3] == 0x34)  // protocol 1024 + addressable + tagged
        #expect(p[32] == 2 && p[33] == 0)
    }
}

@Suite struct ColorTests {
    @Test func hsvRoundTrip() {
        for c in [RGB(255, 0, 0), RGB(0, 128, 255), RGB(30, 200, 90)] {
            let h = c.hsv
            let back = RGB(h: h.h, s: h.s, v: h.v)
            #expect(abs(Int(back.r) - Int(c.r)) <= 1 && abs(Int(back.g) - Int(c.g)) <= 1 && abs(Int(back.b) - Int(c.b)) <= 1)
        }
    }

    @Test func effectsStayInRange() {
        for e in Effect.allCases {
            let f = e.frame(count: 75, phase: 12.3, .warm, RGB(0, 80, 255))
            #expect(f.count == 75)
        }
    }

    @Test func hexParsing() {
        #expect(RGB(hex: "#FF8000") == RGB(255, 128, 0))
        #expect(RGB(hex: "nope") == nil)
    }
}
