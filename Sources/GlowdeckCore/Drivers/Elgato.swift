import Foundation

/// Elgato Key Light / Key Light Air / Ring Light (white, temperature) and Light Strip (colour).
/// Local HTTP API on port 9123, discovered via Bonjour `_elg._tcp`.
public final class ElgatoLight: LightDevice, @unchecked Sendable {
    private let base: String
    private let isColor: Bool
    private let writes = HTTP.Coalescer()
    private var on = true, bri = 1.0, color = RGB.white

    init(serial: String, base: String, name: String, product: String, isColor: Bool) {
        self.base = base
        self.isColor = isColor
        super.init(id: "elgato:\(serial)", brand: "Elgato", name: name, model: product,
                   kind: isColor ? .strip : .keyLight,
                   capabilities: isColor ? [.color, .brightness] : [.temperature, .brightness],
                   maxFPS: 8, address: base)
    }

    private func push() {
        var light: [String: Any] = ["on": on ? 1 : 0, "brightness": Int(max(1, bri * 100))]
        if isColor {
            let hsv = color.hsv
            light["hue"] = hsv.h * 360
            light["saturation"] = hsv.s * 100
            light["brightness"] = Int(max(1, bri * hsv.v * 100))
        } else {
            // Elgato temperature is in mireds, 143 (7000 K) … 344 (2900 K).
            light["temperature"] = Int(max(143, min(344, 1_000_000 / color.approximateKelvin)))
            light["brightness"] = Int(max(1, bri * max(0.05, color.luminance) * 100))
        }
        let body: [String: Any] = ["numberOfLights": 1, "lights": [light]]
        writes.submit { [base] done in
            HTTP.request("PUT", "\(base)/elgato/lights", json: body) { [weak self] _, code in
                self?.setReachable(code == 200)
                done()
            }
        }
    }

    public override func setPower(_ v: Bool) { queue.async { [self] in on = v; push() } }
    public override func setBrightness(_ v: Double) { queue.async { [self] in bri = v; push() } }
    public override func setColor(_ c: RGB) { queue.async { [self] in on = true; color = c; push() } }

    public override func healthCheck() {
        HTTP.request("GET", "\(base)/elgato/accessory-info") { [weak self] _, code in self?.setReachable(code == 200) }
    }
}

public final class ElgatoProvider: DeviceProvider {
    public let family = "Elgato"
    private let bonjour = Bonjour()
    private var known = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        bonjour.browse("_elg._tcp") { [weak self] svc in self?.probe("http://\(svc.host):\(svc.port)") }
    }

    public func scan() {}

    private func probe(_ base: String) {
        HTTP.request("GET", "\(base)/elgato/accessory-info") { [weak self] obj, _ in
            guard let self, let info = obj as? [String: Any] else { return }
            let serial = info.str("serialNumber") ?? base
            guard !self.known.contains(serial) else { return }
            HTTP.request("GET", "\(base)/elgato/lights") { [weak self] lights, _ in
                guard let self else { return }
                let first = ((lights as? [String: Any])?["lights"] as? [[String: Any]])?.first
                let isColor = first?["hue"] != nil
                self.known.insert(serial)
                let product = info.str("productName") ?? "Elgato light"
                let name = (info.str("displayName")).flatMap { $0.isEmpty ? nil : $0 } ?? product
                self.ctx?.found(ElgatoLight(serial: serial, base: base, name: name, product: product, isColor: isColor))
            }
        }
    }
}
