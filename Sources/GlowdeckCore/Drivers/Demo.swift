import Foundation

/// Simulated lights for `--demo` (screenshots, UI work without hardware). They accept every command and do nothing.
public final class DemoLight: LightDevice, @unchecked Sendable {
    init(_ id: String, _ name: String, kind: DeviceKind, leds: Int, brand: String, effects: [String] = []) {
        var caps: Capabilities = [.color, .brightness]
        if leds > 1 { caps.insert(.perLED) }
        if !effects.isEmpty { caps.insert(.nativeEffects) }
        super.init(id: "demo:\(id)", brand: brand, name: name, model: "Simulated", kind: kind,
                   capabilities: caps, ledCount: leds, maxFPS: 25, address: "demo")
        nativeEffects = effects.map { NativeEffect(id: "demo.\($0)", name: $0) }
    }
}

public final class DemoProvider: DeviceProvider {
    public let family = "Demo"
    public init() {}

    public static let lights: [(String, String, DeviceKind, Int, String, String)] = [
        ("desk", "Desk light bar", .strip, 75, "ROBOBLOQ", "Office"),
        ("tv", "TV backlight", .strip, 60, "WLED", "Living room"),
        ("lamp", "Floor lamp", .bulb, 1, "LIFX", "Living room"),
        ("sofa", "Sofa lamp", .bulb, 1, "Philips Hue", "Living room"),
        ("panels", "Hallway panels", .panel, 1, "Nanoleaf", "Hallway"),
        ("bed", "Bedside", .bulb, 1, "WiZ", "Bedroom"),
    ]

    public func start(_ context: ProviderContext) {
        for l in Self.lights {
            context.found(DemoLight(l.0, l.1, kind: l.2, leds: l.3, brand: l.4,
                                    effects: l.2 == .panel ? ["Northern Lights", "Fireworks", "Flames"] : []))
        }
    }

    public func scan() {}
}
