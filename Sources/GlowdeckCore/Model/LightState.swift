import Foundation

/// What a light should be doing. Persisted per device.
public struct LightState: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable { case solid, effect, native }

    public var power: Bool = true
    public var mode: Mode = .solid
    public var color: RGB = .warm
    public var color2: RGB = RGB(0, 80, 255)
    /// 0...1
    public var brightness: Double = 1
    public var effect: Effect = .rainbow
    /// 0...1, 0.5 = normal
    public var speed: Double = 0.5
    public var nativeEffect: NativeEffect?

    public init() {}

    public init(mode: Mode, color: RGB = .warm, color2: RGB = RGB(0, 80, 255),
                brightness: Double = 1, effect: Effect = .rainbow, speed: Double = 0.5) {
        self.mode = mode; self.color = color; self.color2 = color2
        self.brightness = brightness; self.effect = effect; self.speed = speed
    }
}

/// A named look applied to every targeted light at once.
public struct Theme: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var symbol: String
    public var state: LightState
    /// Colours for the preview swatch.
    public var preview: [RGB]

    public static let all: [Theme] = [
        Theme(name: "Focus", symbol: "scope",
              state: LightState(mode: .solid, color: RGB(215, 228, 255), brightness: 0.9),
              preview: [RGB(215, 228, 255), RGB(240, 245, 255)]),
        Theme(name: "Evening", symbol: "sunset.fill",
              state: LightState(mode: .solid, color: RGB(255, 150, 60), brightness: 0.5),
              preview: [RGB(255, 150, 60), RGB(255, 190, 110)]),
        Theme(name: "Sunset", symbol: "sun.horizon.fill",
              state: LightState(mode: .effect, color: RGB(255, 90, 20), color2: RGB(220, 30, 120),
                                brightness: 0.8, effect: .gradient, speed: 0.35),
              preview: [RGB(255, 90, 20), RGB(220, 30, 120)]),
        Theme(name: "Ocean", symbol: "water.waves",
              state: LightState(mode: .effect, color: RGB(0, 60, 255), color2: RGB(0, 220, 200),
                                brightness: 0.8, effect: .wave, speed: 0.4),
              preview: [RGB(0, 60, 255), RGB(0, 220, 200)]),
        Theme(name: "Aurora", symbol: "moon.stars.fill",
              state: LightState(mode: .effect, brightness: 0.8, effect: .aurora, speed: 0.45),
              preview: [RGB(20, 230, 140), RGB(120, 40, 220)]),
        Theme(name: "Fireplace", symbol: "flame.fill",
              state: LightState(mode: .effect, brightness: 0.7, effect: .fire, speed: 0.5),
              preview: [RGB(200, 30, 0), RGB(255, 150, 30)]),
        Theme(name: "Movie", symbol: "film.fill",
              state: LightState(mode: .solid, color: RGB(30, 40, 160), brightness: 0.15),
              preview: [RGB(20, 25, 90), RGB(40, 50, 170)]),
        Theme(name: "Party", symbol: "party.popper.fill",
              state: LightState(mode: .effect, brightness: 1, effect: .rainbow, speed: 0.8),
              preview: [RGB(255, 0, 80), RGB(0, 200, 255)]),
        Theme(name: "Calm", symbol: "leaf.fill",
              state: LightState(mode: .effect, color: RGB(140, 60, 255), brightness: 0.6, effect: .breathe, speed: 0.3),
              preview: [RGB(60, 20, 120), RGB(140, 60, 255)]),
    ]
}

public struct Room: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var symbol: String = "square.split.bottomrightquarter"
    public var deviceIDs: [String] = []
    public init(name: String, symbol: String = "sofa.fill") { self.name = name; self.symbol = symbol }
}
