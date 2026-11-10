import Foundation

/// Software effects rendered by Glowdeck and streamed to lights.
///
/// Every effect is a pure function of (position along the strip/house, phase).
/// `phase` advances by seconds × speed, so changing speed never jumps.
/// Single bulbs get a position from their place in the room, so a wave
/// actually travels through the house.
public enum Effect: String, CaseIterable, Codable, Sendable, Identifiable {
    case rainbow, cycle, breathe, wave, gradient, comet, sparkle, fire, aurora, candle

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    public var symbol: String {
        switch self {
        case .rainbow: return "rainbow"
        case .cycle: return "arrow.triangle.2.circlepath"
        case .breathe: return "wind"
        case .wave: return "water.waves"
        case .gradient: return "circle.lefthalf.filled.righthalf.striped.horizontal"
        case .comet: return "sparkle"
        case .sparkle: return "sparkles"
        case .fire: return "flame.fill"
        case .aurora: return "moon.stars.fill"
        case .candle: return "light.max"
        }
    }

    /// Whether the effect uses the user's two colours (otherwise it has its own palette).
    public var usesColors: Bool {
        switch self {
        case .rainbow, .cycle, .fire, .aurora, .candle: return false
        default: return true
        }
    }

    /// Colour at `x` (0...1 along the light / house) for the given phase.
    public func color(at x: Double, index: Int, phase p: Double, _ c1: RGB, _ c2: RGB) -> RGB {
        switch self {
        case .rainbow:
            return RGB(h: x - p * 0.08)
        case .cycle:
            return RGB(h: p * 0.04)
        case .breathe:
            let f = 0.06 + 0.94 * pow(0.5 - 0.5 * cos(p * 1.2), 2)
            return c1.scaled(f)
        case .wave:
            return c1.mixed(with: c2, 0.5 + 0.5 * sin(2 * .pi * (x * 2 - p * 0.15)))
        case .gradient:
            return c1.mixed(with: c2, 0.5 + 0.5 * cos(2 * .pi * (x - p * 0.05)))
        case .comet:
            let head = (p * 0.16).truncatingRemainder(dividingBy: 1)
            var d = head - x
            if d < 0 { d += 1 }
            let f = pow(max(0, 1 - d / 0.35), 2)
            return c2.scaled(0.08).mixed(with: c1, f)
        case .sparkle:
            // Stateless twinkles: each LED gets a pseudo-random flash per time slot.
            let t = p * 0.6 + hash01(index, 7)
            let slot = floor(t)
            let f = hash01(index, Int(slot)) > 0.6 ? exp(-(t - slot) * 6) : 0
            let spark = c2 == c1 ? RGB.white : c2
            return c1.scaled(0.15).mixed(with: spark, f)
        case .fire:
            let f = 0.55 + 0.25 * sin(p * 3.1 + Double(index) * 0.7) + 0.2 * sin(p * 7.3 + Double(index) * 1.9)
            return RGB(180, 20, 0).mixed(with: RGB(255, 140, 20), f)
        case .aurora:
            let h = 0.42 + 0.18 * sin(2 * .pi * (x * 1.3 + p * 0.03)) + 0.08 * sin(2 * .pi * (x * 3.1 - p * 0.05))
            let v = 0.35 + 0.65 * (0.5 + 0.5 * sin(2 * .pi * (x * 2 + p * 0.07)))
            return RGB(h: h, s: 0.85, v: v)
        case .candle:
            let n = 0.5 * sin(p * 5.3 + Double(index) * 0.3) + 0.3 * sin(p * 11.7 + Double(index)) + 0.2 * sin(p * 2.1)
            return RGB(255, 120, 30).scaled(0.7 + 0.3 * n)
        }
    }

    /// A whole frame for a light with `count` LEDs starting at `offset` along the house.
    public func frame(count: Int, offset: Double = 0, span: Double = 1, phase: Double, _ c1: RGB, _ c2: RGB) -> [RGB] {
        let n = max(1, count)
        return (0..<n).map { i in
            let x = offset + span * Double(i) / Double(n)
            return color(at: x, index: i + Int(offset * 1000), phase: phase, c1, c2)
        }
    }

    /// speed 0...1 → phase rate multiplier (0.5 = normal, 0 ≈ 0.18×, 1 ≈ 5.7×).
    public static func rate(forSpeed s: Double) -> Double {
        pow(2, (s * 100 - 50) / 20)
    }
}

private func hash01(_ a: Int, _ b: Int) -> Double {
    var h = UInt64(bitPattern: Int64(a &* 73_856_093 ^ b &* 19_349_663))
    h ^= h >> 33; h &*= 0xff51afd7ed558ccd; h ^= h >> 33; h &*= 0xc4ceb9fe1a85ec53; h ^= h >> 33
    return Double(h % 10_000) / 10_000
}
