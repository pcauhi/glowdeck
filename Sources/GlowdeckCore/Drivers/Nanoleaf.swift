import Foundation

/// Nanoleaf panels (Aurora/Light Panels, Canvas, Shapes, Elements, Lines).
/// Open API on port 16021; pairing = hold the power button 5–7 s, then request a token.
public final class NanoleafLight: LightDevice, @unchecked Sendable {
    private let base: String
    private let writes = HTTP.Coalescer()

    init(id: String, base: String, name: String, model: String) {
        self.base = base
        super.init(id: "nanoleaf:\(id)", brand: "Nanoleaf", name: name, model: model, kind: .panel,
                   capabilities: [.color, .brightness, .nativeEffects], maxFPS: 5, address: base)
        HTTP.request("GET", "\(base)/effects/effectsList") { [weak self] obj, _ in
            guard let self, let list = obj as? [String] else { return }
            self.nativeEffects = list.map { NativeEffect(id: "nl.\($0)", name: $0) }
            self.changed()
        }
    }

    private func put(_ path: String, _ body: [String: Any]) {
        writes.submit { [base] done in
            HTTP.request("PUT", "\(base)\(path)", json: body) { [weak self] _, code in
                self?.setReachable(code == 204 || code == 200)
                done()
            }
        }
    }

    public override func setPower(_ on: Bool) { put("/state", ["on": ["value": on]]) }
    public override func setBrightness(_ v: Double) { put("/state", ["brightness": ["value": Int(max(1, v * 100))]]) }

    public override func setColor(_ c: RGB) {
        let hsv = c.hsv
        put("/state", ["on": ["value": true], "hue": ["value": Int(hsv.h * 360)], "sat": ["value": Int(hsv.s * 100)]])
    }

    public override func startNativeEffect(_ effect: NativeEffect, speed: Double, color: RGB) {
        put("/effects", ["select": effect.name])
    }

    public override func healthCheck() {
        HTTP.request("GET", "\(base)/state/on") { [weak self] _, code in self?.setReachable(code == 200) }
    }
}

public final class NanoleafProvider: DeviceProvider {
    public let family = "Nanoleaf"
    private let bonjour = Bonjour()
    private var known = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        bonjour.browse("_nanoleafapi._tcp") { [weak self] svc in
            self?.found(id: svc.txt["id"] ?? svc.name, host: "http://\(svc.host):\(svc.port)",
                        name: svc.name, model: svc.txt["md"] ?? "Nanoleaf")
        }
    }

    public func scan() {}

    private func found(id: String, host: String, name: String, model: String) {
        guard !known.contains(id) else { return }
        let key = "nanoleaf:\(id)"
        if let token = Credentials.get(key) {
            known.insert(id)
            ctx?.found(NanoleafLight(id: id, base: "\(host)/api/v1/\(token)", name: name, model: model))
            return
        }
        ctx?.needsPairing(Pairing(
            id: key, title: name,
            instructions: "Hold the power button on your Nanoleaf for 5–7 seconds until the lights flash, then click Pair within 30 seconds."
        ) { [weak self] _, done in
            HTTP.request("POST", "\(host)/api/v1/new") { obj, code in
                guard let token = (obj as? [String: Any])?.str("auth_token") else {
                    done(.failure(PairingError(code == 403 ? "Not in pairing mode yet. Hold the power button, then try again." : "No answer from the panels.")))
                    return
                }
                Credentials.set(key, token)
                self?.ctx?.paired(key)
                self?.found(id: id, host: host, name: name, model: model)
                done(.success(()))
            }
        })
    }
}
