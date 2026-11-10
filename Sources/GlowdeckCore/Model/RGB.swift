import Foundation

/// An 8-bit sRGB colour. The lingua franca between effects, themes and drivers.
public struct RGB: Codable, Hashable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r; self.g = g; self.b = b
    }

    public init(r: Double, g: Double, b: Double) {
        func c(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(c(r), c(g), c(b))
    }

    public static let black = RGB(0, 0, 0)
    public static let white = RGB(255, 255, 255)
    public static let warm = RGB(255, 180, 80)

    /// h, s, v in 0...1 (h wraps).
    public init(h: Double, s: Double = 1, v: Double = 1) {
        let h = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let i = Int(h) % 6
        let f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(r: v, g: t, b: p)
        case 1: self.init(r: q, g: v, b: p)
        case 2: self.init(r: p, g: v, b: t)
        case 3: self.init(r: p, g: q, b: v)
        case 4: self.init(r: t, g: p, b: v)
        default: self.init(r: v, g: p, b: q)
        }
    }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    public var hsv: (h: Double, s: Double, v: Double) {
        let r = Double(self.r) / 255, g = Double(self.g) / 255, b = Double(self.b) / 255
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    public func mixed(with o: RGB, _ t: Double) -> RGB {
        let t = max(0, min(1, t))
        func m(_ a: UInt8, _ b: UInt8) -> Double { (Double(a) + (Double(b) - Double(a)) * t) / 255 }
        return RGB(r: m(r, o.r), g: m(g, o.g), b: m(b, o.b))
    }

    public func scaled(_ f: Double) -> RGB {
        RGB(r: Double(r) / 255 * f, g: Double(g) / 255 * f, b: Double(b) / 255 * f)
    }

    /// Perceived brightness 0...1.
    public var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
    }

    /// CIE xy chromaticity (Wide-gamut D65), as used by Philips Hue.
    public var xy: (x: Double, y: Double) {
        func lin(_ c: UInt8) -> Double {
            let v = Double(c) / 255
            return v > 0.04045 ? pow((v + 0.055) / 1.055, 2.4) : v / 12.92
        }
        let r = lin(r), g = lin(g), b = lin(b)
        let X = r * 0.664511 + g * 0.154324 + b * 0.162028
        let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let sum = X + Y + Z
        return sum == 0 ? (0.3127, 0.3290) : (X / sum, Y / sum)
    }

    /// Rough colour temperature for white-only lights (Elgato Key Light etc.).
    public var approximateKelvin: Double {
        let warmth = (Double(r) - Double(b)) / 255   // -1 (blue) ... 1 (orange)
        return max(2900, min(7000, 5000 - warmth * 2100))
    }

    /// Average of a list of colours.
    public static func average(_ colors: [RGB]) -> RGB {
        guard !colors.isEmpty else { return .black }
        var s = (0, 0, 0)
        for c in colors { s.0 += Int(c.r); s.1 += Int(c.g); s.2 += Int(c.b) }
        let n = colors.count
        return RGB(UInt8(s.0 / n), UInt8(s.1 / n), UInt8(s.2 / n))
    }
}
