import Foundation

/// Philips Hue via the bridge's local v1 REST API (http://<bridge>/api/<username>/…).
/// Pairing = press the link button on the bridge, then request a username within 30 s.
/// The bridge handles ~10 commands/s in total, so lights stream slowly with transitions.
public final class HueLight: LightDevice, @unchecked Sendable {
    private let url: String
    private let isColor: Bool
    private let isCT: Bool
    private let writes = HTTP.Coalescer()

    init(bridge: String, lightID: String, uniqueID: String, name: String, type: String, model: String, url: String) {
        self.url = url
        let t = type.lowercased()
        isColor = t.contains("color light")
        isCT = t.contains("temperature")
        var caps: Capabilities = [.brightness]
        if isColor { caps.insert(.color) } else if isCT { caps.insert(.temperature) }
        if isColor { caps.insert(.nativeEffects) }
        super.init(id: "hue:\(uniqueID)", brand: "Philips Hue", name: name, model: model,
                   kind: .bulb, capabilities: caps, maxFPS: 2, address: bridge)
        if isColor { nativeEffects = [NativeEffect(id: "hue.colorloop", name: "Color loop")] }
    }

    private func put(_ body: [String: Any]) {
        var b = body
        b["transitiontime"] = 4  // ×100 ms; smooths the low update rate
        writes.submit { [url] done in
            HTTP.request("PUT", "\(url)/state", json: b) { [weak self] obj, code in
                // The bridge answers 200 even for unreachable lights; check for an error entry.
                let failed = (obj as? [[String: Any]])?.contains { $0["error"] != nil } ?? false
                self?.setReachable(code == 200 && !failed)
                done()
            }
        }
    }

    public override func setPower(_ on: Bool) { put(["on": on]) }
    public override func setBrightness(_ v: Double) { put(["on": true, "bri": max(1, min(254, Int(v * 254)))]) }

    public override func setColor(_ c: RGB) {
        if isColor {
            let xy = c.xy
            put(["on": true, "effect": "none", "xy": [xy.x, xy.y]])
        } else if isCT {
            put(["on": true, "ct": Int(max(153, min(500, 1_000_000 / c.approximateKelvin)))])
        }
    }

    public override func startNativeEffect(_ effect: NativeEffect, speed: Double, color: RGB) {
        put(["on": true, "effect": "colorloop"])
    }

    public override func healthCheck() {
        HTTP.request("GET", url) { [weak self] obj, code in
            let reachable = ((obj as? [String: Any])?.dict("state")?["reachable"] as? Bool) ?? (code == 200)
            self?.setReachable(reachable)
        }
    }
}

public final class HueProvider: DeviceProvider {
    public let family = "Philips Hue"
    private let bonjour = Bonjour()
    private var bridges = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        bonjour.browse("_hue._tcp") { [weak self] svc in
            self?.bridge(id: svc.txt["bridgeid"] ?? svc.name, host: svc.host, name: svc.name)
        }
    }

    public func scan() {}

    private func bridge(id: String, host: String, name: String) {
        guard !bridges.contains(id) else { return }
        let key = "hue:\(id)"
        if let user = Credentials.get(key) {
            bridges.insert(id)
            loadLights(host: host, user: user)
            return
        }
        ctx?.needsPairing(Pairing(
            id: key, title: name,
            instructions: "Press the round link button on top of your Hue Bridge, then click Pair within 30 seconds."
        ) { [weak self] _, done in
            let host = host
            HTTP.request("POST", "http://\(host)/api", json: ["devicetype": "glowdeck#mac"]) { obj, _ in
                let first = (obj as? [[String: Any]])?.first
                guard let user = first?.dict("success")?.str("username") else {
                    let msg = first?.dict("error")?.str("description") ?? "No answer from the bridge."
                    done(.failure(PairingError(msg.contains("link button") ? "The link button wasn't pressed. Press it, then try again." : msg)))
                    return
                }
                Credentials.set(key, user)
                self?.ctx?.paired(key)
                self?.bridge(id: id, host: host, name: name)
                done(.success(()))
            }
        })
    }

    private func loadLights(host: String, user: String) {
        HTTP.request("GET", "http://\(host)/api/\(user)/lights") { [weak self] obj, _ in
            guard let self, let lights = obj as? [String: [String: Any]] else { return }
            for (lid, l) in lights.sorted(by: { $0.key < $1.key }) {
                self.ctx?.found(HueLight(
                    bridge: host, lightID: lid, uniqueID: l.str("uniqueid") ?? "\(host)-\(lid)",
                    name: l.str("name") ?? "Hue light \(lid)", type: l.str("type") ?? "",
                    model: l.str("productname") ?? l.str("modelid") ?? "Hue",
                    url: "http://\(host)/api/\(user)/lights/\(lid)"))
            }
        }
    }
}
