import Foundation

/// Home Assistant: every `light.*` entity HA knows about (Tuya, Matter, Zigbee, Z-Wave, IKEA, …).
/// Uses the REST API with a long-lived access token (Profile → Security in HA).
public final class HALight: LightDevice, @unchecked Sendable {
    private let base: String
    private let token: String
    private let entity: String
    private let writes = HTTP.Coalescer()
    private var lastColor = RGB.white

    init(base: String, token: String, entity: String, name: String, modes: [String], effects: [String]) {
        self.base = base
        self.token = token
        self.entity = entity
        var caps: Capabilities = []
        if modes.contains(where: { ["rgb", "rgbw", "rgbww", "hs", "xy"].contains($0) }) { caps.insert(.color) }
        else if modes.contains("color_temp") { caps.insert(.temperature) }
        if !modes.contains("onoff") || modes.count > 1 { caps.insert(.brightness) }
        if !effects.isEmpty { caps.insert(.nativeEffects) }
        super.init(id: "ha:\(base)|\(entity)", brand: "Home Assistant", name: name, model: entity,
                   kind: .bulb, capabilities: caps, maxFPS: 2, address: base)
        nativeEffects = effects.map { NativeEffect(id: "ha.\($0)", name: $0) }
    }

    private func call(_ service: String, _ data: [String: Any]) {
        var body = data
        body["entity_id"] = entity
        writes.submit { [base, token] done in
            HTTP.request("POST", "\(base)/api/services/light/\(service)", json: body,
                         headers: ["Authorization": "Bearer \(token)"]) { [weak self] _, code in
                self?.setReachable(code == 200)
                done()
            }
        }
    }

    public override func setPower(_ on: Bool) { call(on ? "turn_on" : "turn_off", [:]) }
    public override func setBrightness(_ v: Double) { call("turn_on", ["brightness": max(1, Int(v * 255))]) }

    public override func setColor(_ c: RGB) {
        lastColor = c
        if capabilities.contains(.color) {
            call("turn_on", ["rgb_color": [c.r, c.g, c.b], "transition": 0.4])
        } else if capabilities.contains(.temperature) {
            call("turn_on", ["color_temp_kelvin": Int(c.approximateKelvin), "transition": 0.4])
        }
    }

    public override func startNativeEffect(_ effect: NativeEffect, speed: Double, color: RGB) {
        call("turn_on", ["effect": effect.name])
    }

    public override func healthCheck() {
        HTTP.request("GET", "\(base)/api/states/\(entity)", headers: ["Authorization": "Bearer \(token)"]) { [weak self] obj, code in
            let state = (obj as? [String: Any])?.str("state")
            self?.setReachable(code == 200 && state != "unavailable")
        }
    }
}

public final class HomeAssistantProvider: DeviceProvider {
    public let family = "Home Assistant"
    private let bonjour = Bonjour()
    private var loaded = Set<String>()
    private var offered = Set<String>()
    private var ctx: ProviderContext?
    public init() {}

    public func start(_ context: ProviderContext) {
        ctx = context
        // Instances the user already connected.
        for key in Credentials.keys(prefix: "ha:") {
            let base = String(key.dropFirst(3))
            if let token = Credentials.get(key) { load(base: base, token: token) }
        }
        bonjour.browse("_home-assistant._tcp") { [weak self] svc in
            let base = svc.txt["internal_url"].flatMap { $0.isEmpty ? nil : $0 } ?? "http://\(svc.host):\(svc.port)"
            self?.offer(base: base, name: svc.txt["location_name"] ?? svc.name)
        }
        offer(base: nil, name: "Home Assistant")
    }

    public func scan() {}

    /// Offer a pairing card. `base == nil` asks the user for the URL too ("http://homeassistant.local:8123 TOKEN").
    private func offer(base: String?, name: String) {
        let id = "ha:\(base ?? "manual")"
        guard !offered.contains(id), base.map({ !loaded.contains($0) }) ?? true else { return }
        offered.insert(id)
        let prompt = base == nil ? "URL and token, e.g. http://homeassistant.local:8123 eyJhbGci…" : "Long-lived access token"
        ctx?.needsPairing(Pairing(
            id: id, title: base == nil ? "Home Assistant (manual)" : name,
            instructions: "Brings in every light Home Assistant controls (Tuya, Matter, Zigbee, IKEA…). In Home Assistant open your Profile → Security → Long-lived access tokens, create one and paste it here.",
            inputPrompt: prompt
        ) { [weak self] input, done in
            var url = base ?? ""
            var token = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if base == nil {
                let parts = token.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { done(.failure(PairingError("Enter the URL, a space, then the token."))); return }
                url = parts[0]; token = parts[1].trimmingCharacters(in: .whitespaces)
            }
            if url.hasSuffix("/") { url.removeLast() }
            HTTP.request("GET", "\(url)/api/", headers: ["Authorization": "Bearer \(token)"]) { _, code in
                guard code == 200 else {
                    done(.failure(PairingError(code == 401 ? "Home Assistant rejected the token." : "Couldn't reach \(url).")))
                    return
                }
                Credentials.set("ha:\(url)", token)
                self?.ctx?.paired(id)
                self?.load(base: url, token: token)
                done(.success(()))
            }
        })
    }

    private func load(base: String, token: String) {
        loaded.insert(base)
        HTTP.request("GET", "\(base)/api/states", headers: ["Authorization": "Bearer \(token)"]) { [weak self] obj, _ in
            guard let self, let states = obj as? [[String: Any]] else { return }
            for s in states {
                guard let entity = s.str("entity_id"), entity.hasPrefix("light.") else { continue }
                let attrs = s.dict("attributes") ?? [:]
                // Skip HA light groups that just wrap other lights.
                if attrs["entity_id"] is [String] { continue }
                self.ctx?.found(HALight(base: base, token: token, entity: entity,
                                        name: attrs.str("friendly_name") ?? entity,
                                        modes: attrs["supported_color_modes"] as? [String] ?? [],
                                        effects: attrs["effect_list"] as? [String] ?? []))
            }
        }
    }
}
